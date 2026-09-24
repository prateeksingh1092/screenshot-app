import AppKit

func drawSizeBadge(_ text: String, above rect: CGRect, in bounds: CGRect) {
    guard rect.width >= 1, rect.height >= 1, !text.isEmpty else { return }
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
    ]
    let textSize = text.size(withAttributes: attributes)
    var origin = CGPoint(x: rect.minX, y: rect.maxY + 6)
    if origin.y + textSize.height > bounds.maxY - 8 {
        origin.y = max(8, rect.minY - textSize.height - 6)
    }
    if origin.x + textSize.width + 8 > bounds.maxX {
        origin.x = max(8, bounds.maxX - textSize.width - 14)
    }
    let background = NSRect(x: origin.x - 6, y: origin.y - 3, width: textSize.width + 12, height: textSize.height + 6)
    NSColor.black.withAlphaComponent(0.72).setFill()
    NSBezierPath(roundedRect: background, xRadius: 6, yRadius: 6).fill()
    text.draw(at: origin, withAttributes: attributes)
}
