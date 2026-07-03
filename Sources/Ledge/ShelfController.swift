import AppKit

final class ShelfController: NSObject {
    private(set) var items: [ShelfItem] = []
    var onInternalDragChanged: ((Bool) -> Void)?

    var isVisible: Bool { panel.isVisible }
    var canBringBack: Bool { !removedStack.isEmpty }

    /// The app menu, shared with the status item. Shown from the shelf's gear
    /// button and on right-click, so the menu stays reachable even when the
    /// menu bar icon is hidden behind the notch on a crowded menu bar.
    var contextMenu: NSMenu? {
        didSet { dropView.menu = contextMenu }
    }

    private let panel: NSPanel
    private let dropView = DropView()
    private let stack = NSStackView()
    private let scroll = NSScrollView()
    private let emptyState = NSStackView()
    private var clearButton: NSButton!
    private let promiseQueue = OperationQueue()
    private var pendingPromises = 0
    private var externalDragActive = false
    private var internalDragActive = false

    /// Groups of items removed together, oldest first. Backs
    /// "Bring Back Last Removed Files".
    private var removedStack: [[ShelfItem]] = []
    private static let removedStackCap = 10

    private var lastCapturedTextHash: Int?
    private var lastCapturedImageHash: Int?

    private static let rowSpacing: CGFloat = 2
    private static let headerHeight: CGFloat = 34
    private static let emptyHeight: CGFloat = 128
    private static let edgeMargin: CGFloat = 16

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: ShelfSize.current.width, height: Self.emptyHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        buildContent()
        dropView.controller = self
    }

    // MARK: - Lifecycle

    func restore() {
        items = Store.load()
        Store.sweepOrphans(keeping: items)
        refresh()
        if !items.isEmpty { show() }
    }

    // MARK: - Drag state from the monitor

    func externalDragStarted() {
        externalDragActive = true
        show()
    }

    func externalDragEnded() {
        externalDragActive = false
        hideIfIdleSoon()
    }

    func internalDragBegan() {
        internalDragActive = true
        onInternalDragChanged?(true)
    }

    func internalDragEnded() {
        internalDragActive = false
        onInternalDragChanged?(false)
        hideIfIdleSoon()
    }

    // MARK: - Items

    func add(urls: [URL], showShelf: Bool = true) {
        guard !urls.isEmpty else { return }
        for url in urls {
            let path = url.path
            if let idx = items.firstIndex(where: { $0.path == path }) {
                items.remove(at: idx)
            }
            items.insert(ShelfItem(id: UUID(), path: path), at: 0)
        }
        refresh()
        if showShelf && !panel.isVisible { show() }
        NSLog("Ledge: added \(urls.count) item(s), shelf now holds \(items.count)")
    }

    func remove(itemID: UUID) {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        items.removeAll { $0.id == itemID }
        pushRemoved([item])
        refresh()
        hideIfIdleSoon()
    }

    func clearAll() {
        guard !items.isEmpty else {
            if !externalDragActive { hide() }
            return
        }
        pushRemoved(items)
        items.removeAll()
        refresh()
        if !externalDragActive { hide() }
    }

    func bringBackLastRemoved() {
        guard let group = removedStack.popLast() else { return }
        let existing = group.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else {
            NSSound.beep()
            return
        }
        for item in existing.reversed() {
            items.removeAll { $0.path == item.path }
            items.insert(item, at: 0)
        }
        refresh()
        show()
        NSLog("Ledge: brought back \(existing.count) item(s)")
    }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    private func pushRemoved(_ removed: [ShelfItem]) {
        guard !removed.isEmpty else { return }
        removedStack.append(removed)
        if removedStack.count > Self.removedStackCap {
            let evicted = removedStack.removeFirst()
            for item in evicted where !items.contains(where: { $0.path == item.path }) {
                scheduleStorageCleanup(for: item)
            }
        }
    }

    // MARK: - Clipboard and imports

    func addClipboardContents() {
        let pb = NSPasteboard.general
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL], !urls.isEmpty {
            add(urls: urls)
            show()
            return
        }
        if addImage(from: pb, prefix: "Clipboard") {
            show()
            return
        }
        if let text = pb.string(forType: .string), !text.isEmpty, let url = Store.saveSnippet(text) {
            add(urls: [url])
            show()
            return
        }
        NSSound.beep()
    }

    /// Saves image or PDF data from a pasteboard into shelf storage and adds
    /// it. Used for clipboard images and Continuity Camera imports.
    @discardableResult
    func addImage(from pb: NSPasteboard, prefix: String) -> Bool {
        guard let (data, ext) = Self.imageData(from: pb),
              let url = Store.saveData(data, ext: ext, prefix: prefix) else { return false }
        add(urls: [url])
        return true
    }

    private static func imageData(from pb: NSPasteboard) -> (data: Data, ext: String)? {
        if let data = pb.data(forType: .png), !data.isEmpty {
            return (data, "png")
        }
        if let data = pb.data(forType: NSPasteboard.PasteboardType("public.jpeg")), !data.isEmpty {
            return (data, "jpg")
        }
        if let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return (png, "png")
        }
        if let data = pb.data(forType: .pdf), !data.isEmpty {
            return (data, "pdf")
        }
        return nil
    }

    /// Called by the clipboard watcher for every new copy. Collects silently,
    /// without popping the shelf open. Deduplicates against the previous
    /// capture because some apps write the pasteboard twice per copy.
    func autoCaptureClipboard(_ pb: NSPasteboard) {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL], !urls.isEmpty {
            add(urls: urls, showShelf: false)
            return
        }
        if let (data, ext) = Self.imageData(from: pb) {
            let hash = data.hashValue
            guard hash != lastCapturedImageHash else { return }
            lastCapturedImageHash = hash
            if let url = Store.saveData(data, ext: ext, prefix: "Clipboard") {
                add(urls: [url], showShelf: false)
            }
            return
        }
        if let text = pb.string(forType: .string), !text.isEmpty {
            let hash = text.hashValue
            guard hash != lastCapturedTextHash else { return }
            lastCapturedTextHash = hash
            if let url = Store.saveSnippet(text) {
                add(urls: [url], showShelf: false)
            }
        }
    }

    // MARK: - Drop handling

    func isInternalDragSource(_ info: NSDraggingInfo) -> Bool {
        info.draggingSource is ItemRowView
    }

    /// Rows forward their drag-over state here so the whole shelf lights up
    /// no matter which part of it the file is hovering.
    func setDropHighlight(_ on: Bool) {
        dropView.setHighlighted(on)
    }

    func handleDrop(_ info: NSDraggingInfo) -> Bool {
        let pb = info.draggingPasteboard

        // 1. Real file URLs (Finder, most apps)
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL], !urls.isEmpty {
            add(urls: urls)
            return true
        }

        // 2. File promises (browser images, Mail attachments, Photos)
        if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)
            as? [NSFilePromiseReceiver], !receivers.isEmpty {
            let dest = Store.newIncomingDir()
            for receiver in receivers {
                pendingPromises += 1
                var counted = false
                receiver.receivePromisedFiles(atDestination: dest, options: [:], operationQueue: promiseQueue) { [weak self] url, error in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if !counted {
                            counted = true
                            self.pendingPromises -= 1
                        }
                        if error == nil {
                            self.add(urls: [url])
                        } else {
                            NSLog("Ledge: file promise failed: \(String(describing: error))")
                            self.hideIfIdleSoon()
                        }
                    }
                }
            }
            return true
        }

        // 3. Plain text becomes a snippet file
        if let text = pb.string(forType: .string), !text.isEmpty, let url = Store.saveSnippet(text) {
            add(urls: [url])
            return true
        }

        return false
    }

    // MARK: - Show / hide

    func show() {
        guard !panel.isVisible else { return }
        positionAtEdge()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            self.panel.animator().alphaValue = 0
        }, completionHandler: {
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
        })
    }

    private func hideIfIdleSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.hideIfIdle()
        }
    }

    private func hideIfIdle() {
        guard items.isEmpty, !externalDragActive, !internalDragActive, pendingPromises == 0 else { return }
        hide()
    }

    // MARK: - Layout

    /// Re-applies position and size settings, called when the user changes
    /// them from the menu.
    func applyLayoutSettings() {
        refresh()
        if panel.isVisible {
            positionAtEdge()
        } else {
            var f = panel.frame
            f.size.width = ShelfSize.current.width
            panel.setFrame(f, display: false)
        }
    }

    private func positionAtEdge() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        let w = ShelfSize.current.width
        let h = desiredHeight(on: screen)
        let m = Self.edgeMargin
        let pos = ShelfPosition.current

        var x: CGFloat
        switch pos {
        case .leftTop, .leftMiddle, .leftBottom:
            x = vf.minX + m
        case .rightTop, .rightMiddle, .rightBottom:
            x = vf.maxX - w - m
        case .mousePointer:
            x = mouse.x + 32
        }

        var y: CGFloat
        switch pos {
        case .leftTop, .rightTop:
            y = vf.maxY - h - m
        case .leftMiddle, .rightMiddle:
            y = vf.midY - h / 2
        case .leftBottom, .rightBottom:
            y = vf.minY + m
        case .mousePointer:
            y = mouse.y - h / 2
        }

        x = min(max(x, vf.minX + 8), vf.maxX - w - 8)
        y = min(max(y, vf.minY + 8), vf.maxY - h - 8)
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }

    private func desiredHeight(on screen: NSScreen?) -> CGFloat {
        if items.isEmpty { return Self.emptyHeight }
        let count = CGFloat(items.count)
        let rowH = ShelfSize.current.rowHeight
        let listH = count * rowH + max(count - 1, 0) * Self.rowSpacing + 16
        let cap = (screen ?? panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        return min(Self.headerHeight + listH, cap * 0.7)
    }

    private func updateFrame(animate: Bool) {
        var f = panel.frame
        let h = desiredHeight(on: panel.screen)
        switch ShelfPosition.current {
        case .leftBottom, .rightBottom:
            f.size.height = h
        case .leftMiddle, .rightMiddle, .mousePointer:
            let midY = f.midY
            f.origin.y = midY - h / 2
            f.size.height = h
        case .leftTop, .rightTop:
            f.origin.y = f.maxY - h
            f.size.height = h
        }
        f.size.width = ShelfSize.current.width
        if let vf = (panel.screen ?? NSScreen.main)?.visibleFrame {
            if f.origin.y < vf.minY { f.origin.y = vf.minY }
            if f.maxY > vf.maxY { f.origin.y = vf.maxY - f.height }
        }
        panel.setFrame(f, display: true, animate: animate && panel.isVisible)
    }

    private func refresh() {
        for v in stack.arrangedSubviews {
            stack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        for item in items {
            let row = ItemRowView(item: item, controller: self)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        emptyState.isHidden = !items.isEmpty
        clearButton.isHidden = items.isEmpty
        updateFrame(animate: true)
        Store.save(items)
    }

    // MARK: - Storage cleanup

    /// Files we copied into our own storage get deleted once their item can no
    /// longer come back via undo. Delayed so a receiving app finishes copying.
    private func scheduleStorageCleanup(for item: ShelfItem) {
        let filesPath = Store.filesDir.path
        guard item.path.hasPrefix(filesPath + "/") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            try? FileManager.default.removeItem(atPath: item.path)
            let parent = item.url.deletingLastPathComponent()
            if parent.path != filesPath,
               let contents = try? FileManager.default.contentsOfDirectory(atPath: parent.path),
               contents.isEmpty {
                try? FileManager.default.removeItem(at: parent)
            }
        }
    }

    // MARK: - Panel setup

    private func configurePanel() {
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.contentView = dropView
    }

    private func buildContent() {
        dropView.wantsLayer = true
        dropView.layer?.cornerRadius = 14

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false
        dropView.addSubview(effect)

        let title = NSTextField(labelWithString: "Ledge")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .secondaryLabelColor

        let clear = FirstMouseButton(
            image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear all") ?? NSImage(),
            target: self,
            action: #selector(clearTapped)
        )
        clear.isBordered = false
        clear.contentTintColor = .secondaryLabelColor
        clear.toolTip = "Clear all items"
        clearButton = clear

        let gear = FirstMouseButton(
            image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Menu") ?? NSImage(),
            target: self,
            action: #selector(gearTapped(_:))
        )
        gear.isBordered = false
        gear.contentTintColor = .secondaryLabelColor
        gear.toolTip = "Ledge menu"

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 10)
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addView(title, in: .leading)
        header.addView(clear, in: .trailing)
        header.addView(gear, in: .trailing)
        effect.addSubview(header)

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(scroll)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Self.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc
        let clip = scroll.contentView

        let iconImage = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: nil) ?? NSImage()
        let icon = NSImageView(image: iconImage)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        icon.contentTintColor = .tertiaryLabelColor
        let hint = NSTextField(labelWithString: "Drop files here")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        emptyState.orientation = .vertical
        emptyState.alignment = .centerX
        emptyState.spacing = 6
        emptyState.addArrangedSubview(icon)
        emptyState.addArrangedSubview(hint)
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(emptyState)

        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: dropView.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: dropView.trailingAnchor),
            effect.topAnchor.constraint(equalTo: dropView.topAnchor),
            effect.bottomAnchor.constraint(equalTo: dropView.bottomAnchor),

            header.topAnchor.constraint(equalTo: effect.topAnchor),
            header.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8),

            doc.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            doc.topAnchor.constraint(equalTo: clip.topAnchor),
            doc.widthAnchor.constraint(equalTo: clip.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),

            emptyState.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])

        refresh()
    }

    @objc private func clearTapped() {
        clearAll()
    }

    @objc private func gearTapped(_ sender: NSButton) {
        contextMenu?.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: sender)
    }
}
