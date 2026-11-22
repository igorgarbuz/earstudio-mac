import AppKit
import ImageIO
import UniformTypeIdentifiers

// Vector-drawn LED ring inspired by the ES100; no downloaded or Android artwork.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let isIOS = CommandLine.arguments.contains("--ios")
let catalog = root.appendingPathComponent(isIOS ? "Apps/iOS/Resources/Assets.xcassets" : "Apps/macOS/Resources/Assets.xcassets")
let destination = catalog.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
var images: [[String: String]] = []
for size in (isIOS ? [1024] : [16, 32, 128, 256, 512]) {
    for scale in (isIOS ? [1] : [1, 2]) {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: Double(pixels) / 1024, y: Double(pixels) / 1024)
        // iOS supplies the corner mask; fill its entire canvas without an inset tile.
        // Preserve the macOS tile geometry and transparent outer margin.
        let outline = isIOS
            ? NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024))
            : NSBezierPath(roundedRect: NSRect(x: 68, y: 68, width: 888, height: 888), xRadius: 195, yRadius: 195)
        // Shared D — Muted green palette, approved for both platforms.
        let backgroundTop = NSColor(calibratedRed: 0.178432375, green: 0.186932375, blue: 0.180557375, alpha: 1)
        let backgroundBottom = NSColor(calibratedRed: 0.059319975, green: 0.063569975, blue: 0.061444975, alpha: 1)
        NSGradient(starting: backgroundTop, ending: backgroundBottom)!.draw(in: outline, angle: -70)
        if !isIOS {
            NSColor.white.withAlphaComponent(0.12).setStroke(); outline.lineWidth = 3; outline.stroke()
        }
        let ringRect = isIOS
            ? NSRect(x: 242, y: 242, width: 540, height: 540)
            : NSRect(x: 278, y: 278, width: 468, height: 468)
        let ring = NSBezierPath(ovalIn: ringRect)
        ring.lineWidth = 52
        // Cast a soft shadow into the opening only, suggesting a slightly raised ring.
        let cg = context.cgContext
        cg.saveGState()
        cg.addEllipse(in: ringRect.insetBy(dx: 26, dy: 26))
        cg.clip()
        cg.setShadow(offset: CGSize(width: 0, height: -5), blur: 10,
                     color: CGColor(gray: 0, alpha: 0.28))
        cg.setStrokeColor(CGColor(gray: 0, alpha: 1))
        cg.setLineWidth(52)
        cg.strokeEllipse(in: ringRect)
        cg.restoreGState()
        NSColor(calibratedRed: 133/255, green: 243/255, blue: 75/255, alpha: 1).setStroke()
        ring.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon-\(size)@\(scale)x.png"
        let output = destination.appendingPathComponent(filename)
        if isIOS {
            let opaque = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            opaque.draw(bitmap.cgImage!, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
            let writer = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(writer, opaque.makeImage()!, nil)
            precondition(CGImageDestinationFinalize(writer))
        } else {
            try bitmap.representation(using: .png, properties: [:])!.write(to: output)
        }
        images.append(isIOS
            ? ["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": filename]
            : ["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
try JSONSerialization.data(withJSONObject: ["images": images, "info": ["version": 1, "author": "xcode"]], options: [.prettyPrinted, .sortedKeys]).write(to: destination.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": ["version": 1, "author": "xcode"]]).write(to: catalog.appendingPathComponent("Contents.json"))
