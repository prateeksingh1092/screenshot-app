import Foundation

/// Where Thumbnails sit on one display (D9, story 90). Every Thumbnail has the same size, so a
/// stack of up to `ThumbnailStackPolicy` maximum never overlaps on a display tall enough for it.
public enum ThumbnailStackLayout {
    /// The fixed Thumbnail size in points.
    public static let cardSize = CGSize(width: 288, height: 216)   // 4 fit on this Mac's 1,015 pt visible built-in display
    public static let margin: CGFloat = 20
    public static let gap: CGFloat = 8

    /// Bottom-left origins, newest first: the newest sits in the display's bottom-right corner and
    /// older ones stack upward. Only a display too short for the whole stack compresses the step.
    public static func origins(count: Int, in visibleFrame: CGRect,
                               cardSize: CGSize = cardSize) -> [CGPoint] {
        guard count > 0 else { return [] }
        let full = cardSize.height + gap
        let room = max(0, visibleFrame.height - 2 * margin - cardSize.height)
        let step = count > 1 ? min(full, room / CGFloat(count - 1)) : 0
        let x = visibleFrame.maxX - margin - cardSize.width
        return (0..<count).map { CGPoint(x: x, y: visibleFrame.minY + margin + CGFloat($0) * step) }
    }
}
