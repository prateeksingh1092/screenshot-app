import Foundation

/// The connected displays, and the only place Frisket turns a point, a window or an ID
/// into a display, or flips between AppKit and ScreenCaptureKit coordinates (ticket 75).
///
/// AppKit global points have a bottom-left origin on the primary display, with y up.
/// ScreenCaptureKit and the window list use global points with a top-left origin, y down.
public struct CaptureDisplays: Equatable, Sendable {
    /// Sorted by ID, so mirrored displays resolve to the lowest ID.
    public let displays: [SelectionDisplay]
    /// The top edge of the primary display (the one at the AppKit origin), in AppKit points.
    public let primaryTop: CGFloat

    public init(_ displays: [SelectionDisplay]) {
        self.displays = displays.sorted { $0.id < $1.id }
        let primary = displays.first { $0.frame.origin == .zero } ?? displays.first
        primaryTop = primary?.frame.maxY ?? 0
    }

    public func display(id: UInt32) -> SelectionDisplay? {
        displays.first { $0.id == id }
    }

    /// AppKit's `NSMouseInRect` rule for unflipped screens: x in [minX, maxX), y in (minY, maxY].
    /// The pointer's y runs from minY + 1 on the bottom row to maxY on the top row, so every pixel,
    /// including the top row, has exactly one owner (D14).
    public func display(at point: CGPoint) -> SelectionDisplay? {
        displays.first {
            point.x >= $0.frame.minX && point.x < $0.frame.maxX
                && point.y > $0.frame.minY && point.y <= $0.frame.maxY
        }
    }

    /// The display holding the largest part of a window. `windowFrame` is in top-left global points.
    public func display(mostOverlapping windowFrame: CGRect) -> SelectionDisplay? {
        let frame = flipped(windowFrame)
        func area(_ display: SelectionDisplay) -> CGFloat {
            let overlap = display.frame.intersection(frame)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        guard let best = displays.max(by: { area($0) < area($1) }), area(best) > 0 else { return nil }
        return best
    }

    /// Converts a point between AppKit and top-left global coordinates. The flip is its own inverse.
    public func flipped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryTop - point.y)
    }

    /// Converts a rectangle between AppKit and top-left global coordinates. The flip is its own inverse.
    public func flipped(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// What ScreenCaptureKit is asked for in area and full-screen capture: one display, a source
/// rectangle in that display's top-left local points snapped to whole pixels, and the output size.
public struct RegionRequest: Equatable, Sendable {
    public let displayID: UInt32
    public let sourceRect: CGRect
    public let pixelWidth: Int
    public let pixelHeight: Int

    /// The Selection `rect` (AppKit global points) clipped to its display and snapped outward to pixels.
    /// A bitmap larger than `decodedByteCeiling` RGBA bytes is refused before the OS allocates it.
    public static func area(_ rect: CGRect, on display: SelectionDisplay,
                            decodedByteCeiling: Int) -> Result<RegionRequest, CaptureSourceFailure> {
        let clipped = rect.intersection(display.frame)
        guard !clipped.isNull, !clipped.isEmpty, display.scale.isFinite, display.scale > 0 else {
            return .failure(.emptyImage)
        }
        let scale = display.scale
        let left = floor((clipped.minX - display.frame.minX) * scale)
        let top = floor((display.frame.maxY - clipped.maxY) * scale)
        let right = ceil((clipped.maxX - display.frame.minX) * scale)
        let bottom = ceil((display.frame.maxY - clipped.minY) * scale)
        let width = right - left, height = bottom - top
        return make(display.id, CGRect(x: left / scale, y: top / scale, width: width / scale, height: height / scale),
                    width: width, height: height, decodedByteCeiling: decodedByteCeiling)
    }

    /// The whole display.
    public static func fullScreen(_ display: SelectionDisplay,
                                  decodedByteCeiling: Int) -> Result<RegionRequest, CaptureSourceFailure> {
        guard display.scale.isFinite, display.scale > 0 else { return .failure(.unavailable) }
        return make(display.id, CGRect(origin: .zero, size: display.frame.size),
                    width: (display.frame.width * display.scale).rounded(),
                    height: (display.frame.height * display.scale).rounded(),
                    decodedByteCeiling: decodedByteCeiling)
    }

    private static func make(_ id: UInt32, _ sourceRect: CGRect, width: CGFloat, height: CGFloat,
                             decodedByteCeiling: Int) -> Result<RegionRequest, CaptureSourceFailure> {
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              width < Double(Int.max), height < Double(Int.max),
              width * height * 4 <= Double(decodedByteCeiling) else { return .failure(.unavailable) }
        return .success(RegionRequest(displayID: id, sourceRect: sourceRect,
                                      pixelWidth: Int(width), pixelHeight: Int(height)))
    }
}
