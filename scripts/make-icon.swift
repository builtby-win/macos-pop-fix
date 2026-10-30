// Renders Resources/AppIcon.png (1024x1024): popcorn emoji on a warm squircle.
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824pt squircle inside a 1024 canvas.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor.white.setFill()
path.fill()
NSGraphicsContext.current?.restoreGraphicsState()

NSGradient(colors: [NSColor(red: 1.0, green: 0.78, blue: 0.30, alpha: 1), NSColor(red: 0.95, green: 0.38, blue: 0.22, alpha: 1)])!
    .draw(in: path, angle: -90)

let emoji = "🍿" as NSString
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont(name: "AppleColorEmoji", size: 560)!]
let s = emoji.size(withAttributes: attrs)
emoji.draw(at: NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2 - 10), withAttributes: attrs)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
