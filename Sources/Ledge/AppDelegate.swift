import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private var statusItem: NSStatusItem?
    private let shelf = ShelfController()
    private var dragMonitor: DragMonitor?
    private var clipboardMonitor: ClipboardMonitor?
    private var hotKey: HotKey?
    private var showHideItem: NSMenuItem?
    private var loginItem: NSMenuItem?
    private var textDragsItem: NSMenuItem?
    private var watchClipboardItem: NSMenuItem?
    private var moveOutItem: NSMenuItem?
    private var positionMenu: NSMenu?
    private var sizeMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: "Ledge") {
            image.isTemplate = true
            status.button?.image = image
        } else {
            status.button?.title = "\u{2B07}"
            NSLog("Ledge: symbol image unavailable, using text fallback")
        }
        status.button?.toolTip = "Ledge"
        let menu = buildMenu()
        status.menu = menu
        shelf.contextMenu = menu
        statusItem = status

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let frame = status.button?.window?.frame ?? .zero
            let screen = NSScreen.main?.frame ?? .zero
            NSLog("Ledge: status item visible=\(status.isVisible) frame=\(NSStringFromRect(frame)) screen=\(NSStringFromRect(screen))")
            if let main = NSScreen.main {
                let left = main.auxiliaryTopLeftArea.map(NSStringFromRect) ?? "none"
                let right = main.auxiliaryTopRightArea.map(NSStringFromRect) ?? "none"
                NSLog("Ledge: auxTopLeft=\(left) auxTopRight=\(right)")
            }
        }

        let monitor = DragMonitor(
            onDragStarted: { [weak self] in self?.shelf.externalDragStarted() },
            onDragEnded: { [weak self] in self?.shelf.externalDragEnded() }
        )
        shelf.onInternalDragChanged = { [weak monitor] active in
            monitor?.isInternalDragActive = active
        }
        monitor.start()
        dragMonitor = monitor

        let clipboard = ClipboardMonitor { [weak self] pb in
            self?.shelf.autoCaptureClipboard(pb)
        }
        clipboard.start()
        clipboardMonitor = clipboard

        let key = HotKey { [weak self] in self?.shelf.toggle() }
        key.register()
        hotKey = key

        shelf.restore()
        NSLog("Ledge is running and watching for drags")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        shelf.show()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Continuity Camera hands the captured photo or scan to the app object,
    /// which forwards it here.
    func receiveImportedImage(from pasteboard: NSPasteboard) -> Bool {
        let ok = shelf.addImage(from: pasteboard, prefix: "Import")
        if ok { shelf.show() }
        return ok
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let bringBack = NSMenuItem(title: "Bring Back Last Removed Files", action: #selector(bringBack(_:)), keyEquivalent: "")
        bringBack.target = self
        menu.addItem(bringBack)

        let clipboard = NSMenuItem(title: "Add Clipboard Contents to Ledge", action: #selector(addClipboard(_:)), keyEquivalent: "")
        clipboard.target = self
        menu.addItem(clipboard)

        let watchClipboard = NSMenuItem(title: "Automatically Add Clipboard", action: #selector(toggleWatchClipboard(_:)), keyEquivalent: "")
        watchClipboard.target = self
        menu.addItem(watchClipboard)
        watchClipboardItem = watchClipboard

        let importItem = NSMenuItem(title: "Import from iPhone or iPad", action: nil, keyEquivalent: "")
        importItem.identifier = NSMenuItem.importFromDeviceIdentifier
        menu.addItem(importItem)

        menu.addItem(.separator())

        let position = NSMenuItem(title: "Window Position", action: nil, keyEquivalent: "")
        let posMenu = NSMenu()
        for pos in ShelfPosition.allCases {
            let item = NSMenuItem(title: pos.title, action: #selector(selectPosition(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pos.rawValue
            item.state = pos == ShelfPosition.current ? .on : .off
            posMenu.addItem(item)
        }
        position.submenu = posMenu
        positionMenu = posMenu
        menu.addItem(position)

        let size = NSMenuItem(title: "Window Size", action: nil, keyEquivalent: "")
        let szMenu = NSMenu()
        for sz in ShelfSize.allCases {
            let item = NSMenuItem(title: sz.title, action: #selector(selectSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = sz.rawValue
            item.state = sz == ShelfSize.current ? .on : .off
            szMenu.addItem(item)
        }
        size.submenu = szMenu
        sizeMenu = szMenu
        menu.addItem(size)

        let showHide = NSMenuItem(title: "Show Ledge", action: #selector(toggleShelf(_:)), keyEquivalent: "\u{F708}")
        showHide.keyEquivalentModifierMask = []
        showHide.target = self
        menu.addItem(showHide)
        showHideItem = showHide

        menu.addItem(.separator())

        let moveOut = NSMenuItem(title: "Remove Original After Drag-Out", action: #selector(toggleMoveOut(_:)), keyEquivalent: "")
        moveOut.target = self
        moveOut.toolTip = "When on, dragging an item out of Ledge sends the original to the Trash instead of leaving a copy."
        menu.addItem(moveOut)
        moveOutItem = moveOut

        let textDrags = NSMenuItem(title: "Show Shelf for Text Drags", action: #selector(toggleTextDrags(_:)), keyEquivalent: "")
        textDrags.target = self
        menu.addItem(textDrags)
        textDragsItem = textDrags

        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        menu.addItem(login)
        loginItem = login

        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Clear Ledge", action: #selector(clearShelf(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        let about = NSMenuItem(title: "About Ledge", action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Ledge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        showHideItem?.title = shelf.isVisible ? "Hide Ledge" : "Show Ledge"
        textDragsItem?.state = (UserDefaults.standard.object(forKey: "IncludeTextDrags") as? Bool ?? true) ? .on : .off
        watchClipboardItem?.state = ClipboardMonitor.isEnabled ? .on : .off
        moveOutItem?.state = UserDefaults.standard.bool(forKey: ShelfController.removeOriginalKey) ? .on : .off
        if Bundle.main.bundlePath.hasSuffix(".app") {
            loginItem?.isHidden = false
            loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            loginItem?.isHidden = true
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(bringBack(_:)) {
            return shelf.canBringBack
        }
        if menuItem.action == #selector(clearShelf(_:)) {
            return !shelf.items.isEmpty
        }
        return true
    }

    // MARK: - Actions

    @objc private func bringBack(_ sender: Any?) {
        shelf.bringBackLastRemoved()
    }

    @objc private func addClipboard(_ sender: Any?) {
        shelf.addClipboardContents()
    }

    @objc private func toggleShelf(_ sender: Any?) {
        shelf.toggle()
    }

    @objc private func clearShelf(_ sender: Any?) {
        shelf.clearAll()
    }

    @objc private func selectPosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let pos = ShelfPosition(rawValue: raw) else { return }
        ShelfPosition.current = pos
        for item in positionMenu?.items ?? [] {
            item.state = item == sender ? .on : .off
        }
        shelf.applyLayoutSettings()
    }

    @objc private func selectSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let size = ShelfSize(rawValue: raw) else { return }
        ShelfSize.current = size
        for item in sizeMenu?.items ?? [] {
            item.state = item == sender ? .on : .off
        }
        shelf.applyLayoutSettings()
    }

    @objc private func toggleWatchClipboard(_ sender: Any?) {
        ClipboardMonitor.isEnabled.toggle()
    }

    @objc private func toggleMoveOut(_ sender: Any?) {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: ShelfController.removeOriginalKey), forKey: ShelfController.removeOriginalKey)
    }

    @objc private func toggleTextDrags(_ sender: Any?) {
        let defaults = UserDefaults.standard
        let current = defaults.object(forKey: "IncludeTextDrags") as? Bool ?? true
        defaults.set(!current, forKey: "IncludeTextDrags")
    }

    @objc private func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func toggleLogin(_ sender: Any?) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Ledge: could not change login item: \(error)")
        }
    }
}
