import AppKit

/// Draws the circular progress arc shown in the menu bar.
enum RingImage {
    /// Color tiers matching the usage level.
    static func color(for fraction: Double) -> NSColor {
        switch fraction {
        case ..<0.8:  return NSColor.systemBlue
        case ..<0.95: return NSColor.systemOrange
        default:      return NSColor.systemRed
        }
    }

    /// A `size`-pt square image with a faint background ring and a foreground arc that
    /// sweeps `fraction` of the circle clockwise from 12 o'clock.
    /// `nil` fraction renders an empty/error ring (faint full circle only).
    static func make(fraction: Double?, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        let lineWidth: CGFloat = size * 0.18
        let inset = lineWidth / 2 + 0.5
        let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let center = NSPoint(x: size / 2, y: size / 2)
        let radius = rect.width / 2

        // Background ring.
        let bg = NSBezierPath(ovalIn: rect)
        bg.lineWidth = lineWidth
        NSColor.tertiaryLabelColor.setStroke()
        bg.stroke()

        guard let fraction, fraction > 0 else { return image }

        // Foreground arc, clockwise from the top.
        let startAngle: CGFloat = 90
        let endAngle = startAngle - CGFloat(min(1, fraction)) * 360
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius,
                      startAngle: startAngle, endAngle: endAngle, clockwise: true)
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        color(for: fraction).setStroke()
        arc.stroke()

        return image
    }
}
