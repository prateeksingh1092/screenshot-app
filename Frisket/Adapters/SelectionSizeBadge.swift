import AppKit

/// Opaque measurement chip. It does not sample the desktop or the capture.
func drawSizeBadge(_ text: String, above rect: CGRect, in bounds: CGRect) {
    guard rect.width >= 1, rect.height >= 1, !text.isEmpty else { return }
    let attributes = sizeBadgeAttributes()
    let textSize = text.size(withAttributes: attributes)
    let padX: CGFloat = 8
    let padY: CGFloat = 4
    let width = textSize.width + padX * 2
    let height = textSize.height + padY * 2
    var frame = NSRect(x: rect.minX, y: rect.maxY + 6, width: width, height: height)
    if frame.maxY > bounds.maxY - 8 {
        frame.origin.y = max(8, rect.minY - height - 6)
    }
    if frame.maxX > bounds.maxX - 8 {
        frame.origin.x = max(8, bounds.maxX - width - 8)
    }
    drawSolidChip(text, in: frame,
                  textOrigin: CGPoint(x: frame.minX + padX, y: frame.minY + padY),
                  attributes: attributes)
}

func drawSolidNotice(_ text: String, at origin: CGPoint, in bounds: CGRect) {
    guard !text.isEmpty else { return }
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
    ]
    let textSize = text.size(withAttributes: attributes)
    let padX: CGFloat = 8
    let padY: CGFloat = 4
    var frame = NSRect(x: origin.x, y: origin.y, width: textSize.width + padX * 2, height: textSize.height + padY * 2)
    if frame.maxX > bounds.maxX - 8 { frame.origin.x = max(8, bounds.maxX - frame.width - 8) }
    if frame.maxY > bounds.maxY - 8 { frame.origin.y = max(8, bounds.maxY - frame.height - 8) }
    drawSolidChip(text, in: frame, textOrigin: CGPoint(x: frame.minX + padX, y: frame.minY + padY), attributes: attributes)
}

/// Black outer stroke, then white inner stroke, then 12 pt corner ticks. The two strokes do not share an inset.
func drawCutMarks(_ selection: CGRect, scale: CGFloat) {
    guard selection.width >= 1, selection.height >= 1, scale > 0 else { return }
    let pixel = 1 / scale
    NSColor.black.setStroke()
    let outer = NSBezierPath(rect: selection.insetBy(dx: -0.5 * pixel, dy: -0.5 * pixel))
    outer.lineWidth = pixel
    outer.stroke()
    NSColor.white.setStroke()
    let inner = NSBezierPath(rect: selection.insetBy(dx: 0.5 * pixel, dy: 0.5 * pixel))
    inner.lineWidth = pixel
    inner.stroke()
    let leg = min(12, min(selection.width, selection.height))
    let thickness = 2 * pixel
    NSColor.white.setFill()
    let x0 = selection.minX
    let y0 = selection.minY
    let x1 = selection.maxX
    let y1 = selection.maxY
    let bars = [
        CGRect(x: x0, y: y0, width: leg, height: thickness),
        CGRect(x: x0, y: y0, width: thickness, height: leg),
        CGRect(x: x1 - leg, y: y0, width: leg, height: thickness),
        CGRect(x: x1 - thickness, y: y0, width: thickness, height: leg),
        CGRect(x: x0, y: y1 - thickness, width: leg, height: thickness),
        CGRect(x: x0, y: y1 - leg, width: thickness, height: leg),
        CGRect(x: x1 - leg, y: y1 - thickness, width: leg, height: thickness),
        CGRect(x: x1 - thickness, y: y1 - leg, width: thickness, height: leg),
    ]
    for bar in bars { NSBezierPath(rect: bar).fill() }
}

private func sizeBadgeAttributes() -> [NSAttributedString.Key: Any] {
    [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
    ]
}

private func drawSolidChip(_ text: String, in frame: NSRect, textOrigin: CGPoint,
                           attributes: [NSAttributedString.Key: Any]) {
    NSColor.black.withAlphaComponent(0.78).setFill()
    NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()
    NSColor.white.setStroke()
    let border = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 7.5, yRadius: 7.5)
    border.lineWidth = 1
    border.stroke()
    text.draw(at: textOrigin, withAttributes: attributes)
}
