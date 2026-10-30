// Renders Resources/AppIcon.png (1024x1024): a drawn popcorn bucket on a warm squircle.
// Pure vector drawing, no emoji/system artwork.
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

// macOS icon grid: 824pt squircle inside a 1024 canvas.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor.white.setFill()
squircle.fill()
NSGraphicsContext.current?.restoreGraphicsState()
NSGradient(colors: [rgb(0xFFC84D), rgb(0xF26338)])!.draw(in: squircle, angle: -90)

// Kernels (back to front): cream puffs with an outline and a few toasted spots.
let kernels: [(CGFloat, CGFloat, CGFloat)] = [
    (330, 600, 62), (700, 600, 62), (400, 660, 74), (630, 665, 74), (515, 700, 82),
    (350, 560, 56), (690, 560, 56), (450, 590, 70), (580, 595, 70), (515, 620, 72),
]
for (x, y, r) in kernels {
    let c = NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    rgb(0xFFF3CC).setFill(); c.fill()
    rgb(0xE9B955).setStroke(); c.lineWidth = 7; c.stroke()
    rgb(0xF2A93B, 0.85).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - r * 0.32, y: y - r * 0.15, width: r * 0.34, height: r * 0.3)).fill()
}

// Bucket: trapezoid with perspective stripes.
let topY: CGFloat = 560, botY: CGFloat = 215
let topL: CGFloat = 290, topR: CGFloat = 740, botL: CGFloat = 360, botR: CGFloat = 670
let trap = NSBezierPath()
trap.move(to: NSPoint(x: botL, y: botY)); trap.line(to: NSPoint(x: botR, y: botY))
trap.line(to: NSPoint(x: topR, y: topY)); trap.line(to: NSPoint(x: topL, y: topY)); trap.close()

NSGraphicsContext.current?.saveGraphicsState()
trap.addClip()
let n = 7
for i in 0..<n {
    let t0 = CGFloat(i) / CGFloat(n), t1 = CGFloat(i + 1) / CGFloat(n)
    let band = NSBezierPath()
    band.move(to: NSPoint(x: botL + (botR - botL) * t0, y: botY))
    band.line(to: NSPoint(x: botL + (botR - botL) * t1, y: botY))
    band.line(to: NSPoint(x: topL + (topR - topL) * t1, y: topY))
    band.line(to: NSPoint(x: topL + (topR - topL) * t0, y: topY))
    band.close()
    (i % 2 == 0 ? rgb(0xE23B2E) : rgb(0xFFFFFF)).setFill()
    band.fill()
}
// Soft shading toward the right edge.
NSGradient(colors: [rgb(0x000000, 0), rgb(0x000000, 0.18)])!.draw(in: NSRect(x: 290, y: 215, width: 450, height: 345), angle: 0)
NSGraphicsContext.current?.restoreGraphicsState()

// Rim
let rim = NSBezierPath(roundedRect: NSRect(x: topL - 14, y: topY - 6, width: topR - topL + 28, height: 34), xRadius: 14, yRadius: 14)
rgb(0xC42A20).setFill(); rim.fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
