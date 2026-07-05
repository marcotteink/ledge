import AppKit
import QuickLookThumbnailing

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Generates and caches QuickLook thumbnails so images show their actual
/// picture on the shelf, PDFs show their first page, and anything without a
/// preview keeps its file-type icon.
enum Thumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    static func request(for url: URL, size: CGFloat, completion: @escaping (NSImage) -> Void) {
        let key = "\(url.path)|\(Int(size))" as NSString
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let image = rep?.nsImage else { return }
            cache.setObject(image, forKey: key)
            DispatchQueue.main.async { completion(image) }
        }
    }
}

/// Buttons inside the shelf must respond even though the panel never becomes key.
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Header grip that drags every shelf item out in a single gesture, closing
/// the "one row at a time" gap. The items leave as one drag session, so
/// Finder and other apps receive them together.
final class DragAllHandle: NSView, NSDraggingSource {
    private weak var controller: ShelfController?
    private var mouseDownEvent: NSEvent?
    private let iconView = NSImageView()

    init(controller: ShelfController) {
        self.controller = controller
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Drag all items") ?? NSImage()
        iconView.image = image
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 22),
            heightAnchor.constraint(equalToConstant: 22),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent, let controller, !controller.items.isEmpty else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard (dx * dx + dy * dy) > 9 else { return }
        mouseDownEvent = nil

        let origin = convert(down.locationInWindow, from: nil)
        let dragItems = controller.items.enumerated().map { index, item -> NSDraggingItem in
            let dragItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
            let offset = CGFloat(min(index, 5)) * 4
            dragItem.setDraggingFrame(
                NSRect(x: origin.x - 20 + offset, y: origin.y - 20 - offset, width: 40, height: 40),
                contents: NSWorkspace.shared.icon(forFile: item.path)
            )
            return dragItem
        }
        beginDraggingSession(with: dragItems, event: down, source: self)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        if context == .withinApplication { return [] }
        if controller?.removeOriginalOnDragOut == true {
            return [.move, .copy]
        }
        return .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        controller?.internalDragBegan()
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let succeeded = operation != []
        controller?.internalDragEnded()
        if succeeded {
            controller?.dragAllOutSucceeded(operation: operation)
        }
    }
}

/// The shelf's content view. Accepts drops of file URLs, file promises, and text.
final class DropView: NSView {
    weak var controller: ShelfController?

    static var acceptedTypes: [NSPasteboard.PasteboardType] {
        var types: [NSPasteboard.PasteboardType] = [.fileURL, .string]
        types += NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        return types
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        registerForDraggedTypes(Self.acceptedTypes)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let controller, !controller.isInternalDragSource(sender) else { return [] }
        setHighlighted(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setHighlighted(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        setHighlighted(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setHighlighted(false)
        return controller?.handleDrop(sender) ?? false
    }

    func setHighlighted(_ on: Bool) {
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = on ? 2 : 0
    }
}

/// One row on the shelf. Acts as a drag source so the item can be dragged
/// back out into any app.
final class ItemRowView: NSView, NSDraggingSource {
    let item: ShelfItem
    private weak var controller: ShelfController?
    private var mouseDownEvent: NSEvent?
    private let removeButton: FirstMouseButton
    private let iconView = NSImageView()
    private var trackingArea: NSTrackingArea?

    init(item: ShelfItem, controller: ShelfController) {
        self.item = item
        self.controller = controller
        self.removeButton = FirstMouseButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove") ?? NSImage(),
            target: nil,
            action: nil
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let metrics = ShelfSize.current
        heightAnchor.constraint(equalToConstant: metrics.rowHeight).isActive = true
        wantsLayer = true
        layer?.cornerRadius = 10
        toolTip = item.path

        let icon = NSWorkspace.shared.icon(forFile: item.path)
        icon.size = NSSize(width: metrics.iconSize, height: metrics.iconSize)
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 4
        iconView.layer?.masksToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: metrics.iconSize).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: metrics.iconSize).isActive = true

        // Swap in a real preview (image contents, PDF first page) when
        // QuickLook can make one; otherwise the file-type icon stays.
        Thumbnails.request(for: item.url, size: metrics.iconSize) { [weak iconView] thumb in
            iconView?.image = thumb
        }

        let name = NSTextField(labelWithString: item.displayName)
        name.font = .systemFont(ofSize: 12, weight: .medium)
        name.lineBreakMode = .byTruncatingMiddle
        name.maximumNumberOfLines = 1
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let sub = NSTextField(labelWithString: item.subtitle)
        sub.font = .systemFont(ofSize: 10)
        sub.textColor = .secondaryLabelColor
        sub.lineBreakMode = .byTruncatingMiddle
        sub.maximumNumberOfLines = 1
        sub.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textStack = NSStackView(views: [name, sub])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let content = NSStackView(views: [iconView, textStack])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        removeButton.isBordered = false
        removeButton.contentTintColor = .secondaryLabelColor
        removeButton.isHidden = true
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Rows cover most of the shelf, so they must accept drops themselves
        // or the usable drop area shrinks to the gaps between them.
        registerForDraggedTypes(DropView.acceptedTypes)
    }

    // MARK: - Drop forwarding

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let controller, !controller.isInternalDragSource(sender) else { return [] }
        controller.setDropHighlight(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        controller?.setDropHighlight(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        controller?.setDropHighlight(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        controller?.setDropHighlight(false)
        return controller?.handleDrop(sender) ?? false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Without this, the panel's movable-by-background behavior hijacks the
    /// mouse drag and moves the whole shelf instead of dragging the file out.
    override var mouseDownCanMoveWindow: Bool { false }

    /// Route clicks anywhere on the row (except the remove button) to the row
    /// itself so dragging works over the labels and icon too.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        if view === removeButton { return view }
        return view == nil ? nil : self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        removeButton.isHidden = false
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        removeButton.isHidden = true
        layer?.backgroundColor = nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            NSWorkspace.shared.open(item.url)
            return
        }
        mouseDownEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard (dx * dx + dy * dy) > 9 else { return }
        mouseDownEvent = nil
        startDrag(with: down)
    }

    private func startDrag(with event: NSEvent) {
        let dragItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        let dragImage: NSImage
        if let current = iconView.image {
            dragImage = current
        } else {
            dragImage = NSWorkspace.shared.icon(forFile: item.path)
        }
        let p = convert(event.locationInWindow, from: nil)
        dragItem.setDraggingFrame(
            NSRect(x: p.x - 24, y: p.y - 24, width: 48, height: 48),
            contents: dragImage
        )
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    @objc private func removeTapped() {
        controller?.remove(itemID: item.id)
    }

    // MARK: - Per-item context menu

    /// Right-clicking a row gets item actions. The app menu stays reachable
    /// from the gear button and by right-clicking the shelf background.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open", action: #selector(openItem), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(revealItem), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)
        let copy = NSMenuItem(title: "Copy", action: #selector(copyItem), keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)
        menu.addItem(.separator())
        let remove = NSMenuItem(title: "Remove from Ledge", action: #selector(removeTapped), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        return menu
    }

    @objc private func openItem() {
        NSWorkspace.shared.open(item.url)
    }

    @objc private func revealItem() {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Text snippets copy their contents so they paste straight into any
    /// text field; everything else copies as a file for pasting in Finder.
    @objc private func copyItem() {
        let pb = NSPasteboard.general
        pb.clearContents()
        if item.url.pathExtension == "txt",
           item.path.hasPrefix(Store.filesDir.path + "/"),
           let text = try? String(contentsOf: item.url, encoding: .utf8) {
            controller?.noteClipboardWrite(text)
            pb.setString(text, forType: .string)
        } else {
            pb.writeObjects([item.url as NSURL])
        }
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        if context == .withinApplication { return [] }
        // In move mode, offer move (preferred) and copy so a same-volume drop
        // into Finder becomes an instant atomic move. Otherwise copy only, so
        // the original always stays put.
        if controller?.removeOriginalOnDragOut == true {
            return [.move, .copy]
        }
        return .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        controller?.internalDragBegan()
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let succeeded = operation != []
        controller?.internalDragEnded()
        if succeeded {
            controller?.dragOutSucceeded(itemID: item.id, operation: operation)
        }
    }
}
