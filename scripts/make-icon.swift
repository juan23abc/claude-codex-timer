import AppKit
import Foundation

// Original vector artwork; no external assets or trademarks.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
        (transform as NSAffineTransform).concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 46, y: 46, width: 932, height: 932), xRadius: 208, yRadius: 208)
        NSGradient(starting: NSColor(calibratedRed: 0.85, green: 0.49, blue: 0.34, alpha: 1), ending: NSColor(calibratedRed: 0.66, green: 0.29, blue: 0.20, alpha: 1))!.draw(in: background, angle: -65)
        let ink = NSColor(calibratedRed: 1, green: 0.96, blue: 0.86, alpha: 1)
        ink.setStroke(); ink.setFill()
        let dial = NSBezierPath(ovalIn: NSRect(x: 234, y: 201, width: 556, height: 556))
        dial.lineWidth = 49; dial.stroke()
        let cap = NSBezierPath(roundedRect: NSRect(x: 440, y: 810, width: 144, height: 44), xRadius: 22, yRadius: 22); cap.fill()
        let stem = NSBezierPath(); stem.move(to: NSPoint(x: 512, y: 750)); stem.line(to: NSPoint(x: 512, y: 820)); stem.lineWidth = 42; stem.stroke()
        let hand = NSBezierPath(); hand.move(to: NSPoint(x: 512, y: 672)); hand.line(to: NSPoint(x: 512, y: 479)); hand.line(to: NSPoint(x: 621, y: 401)); hand.lineWidth = 44; hand.lineCapStyle = .round; hand.lineJoinStyle = .round; hand.stroke()
        NSBezierPath(ovalIn: NSRect(x: 485, y: 452, width: 54, height: 54)).fill()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
