import AppKit

enum Icons {
    /// Popcorn bucket + kernels, drawn as a template image so it follows the menu bar tint.
    static let menuBar: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            // Kernels
            for (x, y, r) in [(4.6, 12.4, 3.0), (9.0, 14.0, 3.4), (13.4, 12.4, 3.0), (7.0, 11.2, 2.6), (11.4, 11.2, 2.6)] as [(Double, Double, Double)] {
                NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
            }
            // Bucket
            let bucket = NSBezierPath()
            bucket.move(to: NSPoint(x: 4.2, y: 0.8))
            bucket.line(to: NSPoint(x: 13.8, y: 0.8))
            bucket.line(to: NSPoint(x: 15.2, y: 10.2))
            bucket.line(to: NSPoint(x: 2.8, y: 10.2))
            bucket.close()
            bucket.fill()
            // Stripes cut out of the bucket
            NSGraphicsContext.current?.compositingOperation = .clear
            for x in [6.3, 9.0, 11.7] {
                let stripe = NSBezierPath()
                stripe.lineWidth = 1.1
                stripe.move(to: NSPoint(x: x - 0.15 * (x - 9) / 2.7, y: 1.8))
                stripe.line(to: NSPoint(x: x + 0.2 * (x - 9) / 2.7, y: 9.2))
                stripe.stroke()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "PopFix"
        return img
    }()
}
