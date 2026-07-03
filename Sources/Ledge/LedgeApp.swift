import AppKit

/// NSApplication subclass so Ledge sits at the end of the responder chain as a
/// services requestor. This is what lets macOS enable the Continuity Camera
/// "Import from iPhone or iPad" menu item and hand us the captured image.
final class LedgeApp: NSApplication {
    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        if let returnType,
           NSImage.imageTypes.contains(returnType.rawValue) || returnType == .pdf {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }
}

extension LedgeApp: NSServicesMenuRequestor {
    func readSelection(from pasteboard: NSPasteboard) -> Bool {
        (delegate as? AppDelegate)?.receiveImportedImage(from: pasteboard) ?? false
    }

    func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        false
    }
}
