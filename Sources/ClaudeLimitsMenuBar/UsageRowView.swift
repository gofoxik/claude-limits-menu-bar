import AppKit

/// A dropdown row showing one usage window: title + percentage on top,
/// a horizontal progress bar below, and a reset caption — mirroring the
/// bars on Claude Code's `/usage` screen.
final class UsageRowView: NSView {
    private let title: String
    private let percent: Double      // 0–100
    private let resetText: String

    init(title: String, percent: Double, resetText: String, width: CGFloat = 300) {
        self.title = title
        self.percent = percent
        self.resetText = resetText
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 58))
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let pad: CGFloat = 16
        let fraction = max(0, min(1, percent / 100))
        let fillColor = RingImage.color(for: fraction)

        // Title (top-left).
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        (title as NSString).draw(at: NSPoint(x: pad, y: 9), withAttributes: titleAttrs)

        // Percentage (top-right).
        let pctStr = "\(Int(percent.rounded()))%" as NSString
        let pctSize = pctStr.size(withAttributes: titleAttrs)
        pctStr.draw(at: NSPoint(x: bounds.width - pad - pctSize.width, y: 9),
                    withAttributes: titleAttrs)

        // Progress bar track.
        let barRect = NSRect(x: pad, y: 30, width: bounds.width - pad * 2, height: 7)
        let radius = barRect.height / 2
        let track = NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius)
        NSColor.tertiaryLabelColor.withAlphaComponent(0.4).setFill()
        track.fill()

        // Progress bar fill.
        if fraction > 0 {
            let fillWidth = max(barRect.height, barRect.width * fraction)
            let fillRect = NSRect(x: barRect.minX, y: barRect.minY,
                                  width: fillWidth, height: barRect.height)
            let fill = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
            fillColor.setFill()
            fill.fill()
        }

        // Reset caption.
        if !resetText.isEmpty {
            let resetAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            (resetText as NSString).draw(at: NSPoint(x: pad, y: 41), withAttributes: resetAttrs)
        }
    }
}
