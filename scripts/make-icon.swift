import AppKit

// Draws the Ledge app icon: a rounded square with a deep blue gradient and a
// white tray symbol, following the macOS Big Sur+ icon grid.

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let inset = size * 0.098
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = rect.width * 0.225
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

let top = NSColor(calibratedRed: 0.20, green: 0.45, blue: 1.00, alpha: 1)
let bottom = NSColor(calibratedRed: 0.04, green: 0.10, blue: 0.32, alpha: 1)
NSGraphicsContext.current?.saveGraphicsState()
path.addClip()
NSGradient(colors: [top, bottom])?.draw(in: rect, angle: -90)

// subtle inner shelf line detail
let shelfY = rect.minY + rect.height * 0.30
let shelf = NSBezierPath()
shelf.move(to: NSPoint(x: rect.minX + rect.width * 0.22, y: shelfY))
shelf.line(to: NSPoint(x: rect.maxX - rect.width * 0.22, y: shelfY))
shelf.lineWidth = size * 0.018
shelf.lineCapStyle = .round
NSColor.white.withAlphaComponent(0.35).setStroke()
shelf.stroke()
NSGraphicsContext.current?.restoreGraphicsState()

let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .medium)
    .applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    let scale = (rect.width * 0.52) / max(s.width, s.height)
    let w = s.width * scale
    let h = s.height * scale
    let drawRect = NSRect(
        x: rect.midX - w / 2,
        y: rect.midY - h / 2 + rect.height * 0.02,
        width: w,
        height: h
    )
    symbol.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to render icon\n", stderr)
    exit(1)
}
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png")
try! png.write(to: out)
print("wrote \(out.path)")
