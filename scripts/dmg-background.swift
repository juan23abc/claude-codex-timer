import AppKit

// Native vector/text artwork for the Finder installation window.
let size = NSSize(width: 660, height: 400)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.92, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}
let ink = NSColor(calibratedWhite: 0.20, alpha: 1)
let muted = NSColor(calibratedWhite: 0.40, alpha: 1)
label("Claude Codex Timer", x: 42, y: 327, size: 27, weight: .semibold, color: ink)
label("Drag the app into Applications to install.", x: 42, y: 297, size: 15, weight: .regular, color: muted)
label("→", x: 307, y: 178, size: 42, weight: .light, color: NSColor(calibratedRed: 0.76, green: 0.37, blue: 0.25, alpha: 1))
label("macOS 13+   ·   Apple silicon + Intel", x: 42, y: 58, size: 12, weight: .medium, color: muted)
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
