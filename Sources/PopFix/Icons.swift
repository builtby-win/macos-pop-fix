import AppKit

enum Icons {
    /// Popcorn bucket + kernels with a wrench across the front, drawn as a template image
    /// so it follows the menu bar tint. 18pt grid.
    static let menuBar: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let ctx = NSGraphicsContext.current
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Kernels
            for (x, y, r) in [(4.2, 11.6, 2.6), (8.2, 13.6, 3.0), (12.2, 11.8, 2.7), (6.4, 10.4, 2.3), (10.4, 10.4, 2.3)] as [(Double, Double, Double)] {
                NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
            }

            // Bucket, with stripes cut out
            let bucket = NSBezierPath()
            bucket.move(to: NSPoint(x: 3.6, y: 0.8))
            bucket.line(to: NSPoint(x: 12.8, y: 0.8))
            bucket.line(to: NSPoint(x: 14.2, y: 9.6))
            bucket.line(to: NSPoint(x: 2.2, y: 9.6))
            bucket.close()
            bucket.fill()
            ctx?.compositingOperation = .clear
            for (x0, x1) in [(5.4, 5.1), (8.2, 8.2), (11.0, 11.3)] as [(Double, Double)] {
                let stripe = NSBezierPath()
                stripe.lineWidth = 1.0
                stripe.move(to: NSPoint(x: x0, y: 1.8))
                stripe.line(to: NSPoint(x: x1, y: 8.6))
                stripe.stroke()
            }

            // Wrench: handle + open-end head, with a clear halo so it reads over the bucket.
            let t = NSAffineTransform()
            t.translateX(by: 13.2, yBy: 12.4)
            t.rotate(byDegrees: 45)
            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: -11.5, y: 0)); handle.line(to: NSPoint(x: 0, y: 0))
            handle.lineCapStyle = .round
            let head = NSBezierPath(ovalIn: NSRect(x: -3.2, y: -3.2, width: 6.4, height: 6.4))
            let slot = NSBezierPath(rect: NSRect(x: 0.3, y: -1.15, width: 5, height: 2.3))
            for p in [handle, head, slot] { p.transform(using: t as AffineTransform) }

            ctx?.compositingOperation = .clear
            handle.lineWidth = 4.4; handle.stroke()
            head.lineWidth = 2.4; head.stroke(); head.fill()
            ctx?.compositingOperation = .sourceOver
            handle.lineWidth = 2.2; handle.stroke()
            head.fill()
            ctx?.compositingOperation = .clear
            slot.fill()
            ctx?.compositingOperation = .sourceOver
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "PopFix"
        return img
    }()
}
