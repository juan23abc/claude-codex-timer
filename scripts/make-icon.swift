import AppKit
import ImageIO
import UniformTypeIdentifiers

// Package the approved artwork at every standard macOS icon size.
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/make-icon.swift <output.iconset>\n", stderr)
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let artwork = project.appendingPathComponent("Resources/Icon/AppIcon.png")
guard let source = CGImageSourceCreateWithURL(artwork as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width == image.height else {
    fputs("App icon artwork must be a readable square PNG: \(artwork.path)\n", stderr)
    exit(1)
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
            bytesPerRow: pixels * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { fatalError("Could not allocate icon bitmap") }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        let destinationURL = output.appendingPathComponent(name)
        guard let bitmap = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fatalError("Could not create \(name)")
        }
        CGImageDestinationAddImage(destination, bitmap, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(name)") }
    }
}
