import AppKit

// Vector-drawn LED ring inspired by the ES100; no downloaded or Android artwork.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let catalog = root.appendingPathComponent("Resources/Assets.xcassets")
let destination = catalog.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: Double(pixels) / 1024, y: Double(pixels) / 1024)
        let rect = NSRect(x: 68, y: 68, width: 888, height: 888)
        let outline = NSBezierPath(roundedRect: rect, xRadius: 195, yRadius: 195)
        NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.17, alpha: 1), ending: NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.06, alpha: 1))!.draw(in: outline, angle: -70)
        NSColor.white.withAlphaComponent(0.12).setStroke(); outline.lineWidth = 3; outline.stroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: 278, y: 278, width: 468, height: 468))
        ring.lineWidth = 52
        NSColor(calibratedRed: 133/255, green: 243/255, blue: 75/255, alpha: 1).setStroke()
        ring.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon-\(size)@\(scale)x.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(filename))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
try JSONSerialization.data(withJSONObject: ["images": images, "info": ["version": 1, "author": "xcode"]], options: [.prettyPrinted, .sortedKeys]).write(to: destination.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": ["version": 1, "author": "xcode"]]).write(to: catalog.appendingPathComponent("Contents.json"))
