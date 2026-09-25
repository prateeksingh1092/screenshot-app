import Foundation

/// The square of device pixels the Loupe magnifies, in one display's pixel grid.
public struct LoupeSample: Equatable, Sendable {
    public let displayID: UInt32
    public let scale: CGFloat
    /// The square's top-left device pixel, display-local, top-left origin.
    public let left: Int
    public let top: Int
    /// Device pixels per side.
    public let span: Int
    /// The pixel under the pointer, within the square, top-left origin.
    public let column: Int
    public let row: Int

    public init(displayID: UInt32, scale: CGFloat, left: Int, top: Int, span: Int, column: Int, row: Int) {
        self.displayID = displayID
        self.scale = scale
        self.left = left
        self.top = top
        self.span = span
        self.column = column
        self.row = row
    }

    /// Display-local points, top-left origin: the capture route's `sourceRect`.
    public var sourceRect: CGRect {
        CGRect(x: CGFloat(left) / scale, y: CGFloat(top) / scale,
               width: CGFloat(span) / scale, height: CGFloat(span) / scale)
    }
}

/// Pure Loupe geometry. Pointers are AppKit points, bottom-left origin, where a
/// pointer's coordinates are the top-left corner of the pixel under it: x in
/// [minX, maxX), y in (minY, maxY] (D14).
public enum Loupe {
    public static let span = 15

    /// The `span`-pixel square around the pixel under `pointer`. Near a display edge the
    /// square stays whole and inside the display, and the marked pixel moves off centre.
    public static func sample(at pointer: CGPoint, on display: SelectionDisplay, span: Int = span) -> LoupeSample? {
        let scale = display.scale
        guard scale > 0, scale.isFinite, pointer.x.isFinite, pointer.y.isFinite else { return nil }
        let width = Int((display.frame.width * scale).rounded())
        let height = Int((display.frame.height * scale).rounded())
        let side = min(span, width, height)
        guard side > 0 else { return nil }
        let x = min(max(Int(floor((pointer.x - display.frame.minX) * scale)), 0), width - 1)
        let y = min(max(Int(floor((display.frame.maxY - pointer.y) * scale)), 0), height - 1)
        let left = min(max(x - side / 2, 0), width - side)
        let top = min(max(y - side / 2, 0), height - side)
        return LoupeSample(displayID: display.id, scale: scale, left: left, top: top, span: side,
                           column: x - left, row: y - top)
    }

    /// Where a Loupe of `size` sits beside `pointer`, both in `bounds` coordinates (the
    /// display's local points, bottom-left origin). It prefers above and to the right,
    /// flips per axis to stay inside `bounds`, and keeps `gap` points from the pointer.
    public static func frame(size: CGSize, beside pointer: CGPoint, in bounds: CGRect, gap: CGFloat = 20) -> CGRect {
        func place(_ point: CGFloat, length: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
            if point + gap + length <= high { return point + gap }
            if point - gap - length >= low { return point - gap - length }
            return min(max(point + gap, low), max(low, high - length))
        }
        return CGRect(x: place(pointer.x, length: size.width, low: bounds.minX, high: bounds.maxX),
                      y: place(pointer.y, length: size.height, low: bounds.minY, high: bounds.maxY),
                      width: size.width, height: size.height)
    }
}
