import AppKit

/// Watches the system drag pasteboard to detect when the user starts dragging
/// files (or text) anywhere in macOS. Uses a lightweight poll of
/// NSEvent.pressedMouseButtons plus the drag pasteboard's changeCount, which
/// needs no accessibility permissions.
final class DragMonitor {
    /// Set to true while the shelf itself is the drag source, so we do not
    /// react to our own drags.
    var isInternalDragActive = false

    private let dragPasteboard = NSPasteboard(name: .drag)
    private var lastChangeCount: Int
    private var dragActive = false
    private var timer: Timer?
    private let onDragStarted: () -> Void
    private let onDragEnded: () -> Void
    private let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes)

    init(onDragStarted: @escaping () -> Void, onDragEnded: @escaping () -> Void) {
        self.onDragStarted = onDragStarted
        self.onDragEnded = onDragEnded
        self.lastChangeCount = dragPasteboard.changeCount
    }

    func start() {
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let leftButtonDown = (NSEvent.pressedMouseButtons & 1) != 0

        if dragActive {
            if !leftButtonDown {
                dragActive = false
                lastChangeCount = dragPasteboard.changeCount
                onDragEnded()
            }
            return
        }

        if leftButtonDown {
            let count = dragPasteboard.changeCount
            if count != lastChangeCount && !isInternalDragActive && pasteboardLooksInteresting() {
                lastChangeCount = count
                dragActive = true
                onDragStarted()
            }
        } else {
            lastChangeCount = dragPasteboard.changeCount
        }
    }

    private func pasteboardLooksInteresting() -> Bool {
        guard let types = dragPasteboard.types else { return false }
        if types.contains(.fileURL) { return true }
        if types.contains(where: { promiseTypes.contains($0.rawValue) }) { return true }
        let includeText = UserDefaults.standard.object(forKey: "IncludeTextDrags") as? Bool ?? true
        if includeText && types.contains(.string) { return true }
        return false
    }
}
