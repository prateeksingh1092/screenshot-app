import Foundation

/// Pure selection geometry in global, bottom-left-origin points. The display
/// frame is fixed for the session; callers supply a finite positive frame/scale
/// with a whole-device-pixel display size. Coordinates snap to the nearest pixel.
public struct SelectionGeometry: Sendable {
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let option = Self(rawValue: 1 << 0)
        public static let shift = Self(rawValue: 1 << 1)
        public static let space = Self(rawValue: 1 << 2)
    }

    public private(set) var rect: CGRect
    private let display: CGRect
    private let scale: CGFloat
    private var anchor: CGPoint?
    private var endpoint: CGPoint?
    private var shiftOrigin: CGPoint?
    private var horizontalLock: Bool?
    private var spaceOrigin: (point: CGPoint, rect: CGRect)?
    private var pointerOffset = CGPoint.zero

    public init(displayFrame: CGRect, scale: CGFloat) {
        display = displayFrame
        self.scale = scale
        let width = min(320, displayFrame.width), height = min(180, displayFrame.height)
        rect = CGRect(x: displayFrame.midX - width / 2, y: displayFrame.midY - height / 2,
                      width: width, height: height)
        rect.origin = clamped(rect.origin)
    }

    /// Start a new corner-anchored drag, clearing the previous drag's modifiers.
    public mutating func begin(at point: CGPoint) {
        let point = clamped(point)
        anchor = point
        endpoint = point
        shiftOrigin = nil
        horizontalLock = nil
        spaceOrigin = nil
        pointerOffset = .zero
        rect = CGRect(origin: point, size: .zero)
    }

    /// Feed pointer movement AND modifier transitions (at the current pointer).
    /// Shift chooses the first dominant movement axis and holds it until released.
    /// Space takes precedence over resizing; Option keeps the anchor as centre.
    public mutating func update(to point: CGPoint, modifiers: Modifiers = []) {
        guard anchor != nil else { return }
        let pointer = clamped(point)
        // Modifier releases still count while Space temporarily owns movement.
        if !modifiers.contains(.shift) {
            shiftOrigin = nil
            horizontalLock = nil
        }
        if modifiers.contains(.space) {
            if spaceOrigin == nil { spaceOrigin = (pointer, rect) }
            if let origin = spaceOrigin {
                translate(dx: origin.rect.minX + pointer.x - origin.point.x - rect.minX,
                          dy: origin.rect.minY + pointer.y - origin.point.y - rect.minY)
            }
            return
        }
        if spaceOrigin != nil, let endpoint {
            pointerOffset = CGPoint(x: endpoint.x - pointer.x, y: endpoint.y - pointer.y)
            spaceOrigin = nil
        }
        guard let anchor else { return }
        var point = clamped(CGPoint(x: pointer.x + pointerOffset.x, y: pointer.y + pointerOffset.y))
        if modifiers.contains(.shift) {
            if shiftOrigin == nil { shiftOrigin = endpoint }
            if let origin = shiftOrigin {
                let dx = point.x - origin.x, dy = point.y - origin.y
                if horizontalLock == nil, dx != 0 || dy != 0 { horizontalLock = abs(dx) >= abs(dy) }
                if let horizontalLock {
                    if horizontalLock { point.y = origin.y } else { point.x = origin.x }
                }
            }
        }
        endpoint = point
        if modifiers.contains(.option) {
            let halfWidth = min(abs(point.x - anchor.x), anchor.x - display.minX, display.maxX - anchor.x)
            let halfHeight = min(abs(point.y - anchor.y), anchor.y - display.minY, display.maxY - anchor.y)
            rect = CGRect(x: anchor.x - halfWidth, y: anchor.y - halfHeight,
                          width: halfWidth * 2, height: halfHeight * 2)
            endpoint = CGPoint(x: anchor.x + (point.x < anchor.x ? -halfWidth : halfWidth),
                               y: anchor.y + (point.y < anchor.y ? -halfHeight : halfHeight))
            return
        }
        rect = CGRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                      width: abs(point.x - anchor.x), height: abs(point.y - anchor.y))
    }

    /// Translate by device pixels; positive y is up. Nudges also rebase an active drag.
    public mutating func nudge(dx: Int, dy: Int) {
        let before = rect.origin
        translate(dx: CGFloat(dx) / scale, dy: CGFloat(dy) / scale)
        let delta = CGPoint(x: rect.minX - before.x, y: rect.minY - before.y)
        pointerOffset.x += delta.x
        pointerOffset.y += delta.y
        if let origin = spaceOrigin {
            spaceOrigin = (origin.point, origin.rect.offsetBy(dx: delta.x, dy: delta.y))
        }
    }

    /// Resize by device pixels, keeping the bottom-left origin fixed and at
    /// least one pixel per dimension, within the origin display. A zero-area
    /// drag on the top/right boundary moves inward to make room for that pixel.
    public mutating func resize(dw: Int, dh: Int) {
        let before = rect
        rect.origin.x = min(rect.minX, display.maxX - 1 / scale)
        rect.origin.y = min(rect.minY, display.maxY - 1 / scale)
        rect.size.width = min(max(rect.width + CGFloat(dw) / scale, 1 / scale), display.maxX - rect.minX)
        rect.size.height = min(max(rect.height + CGFloat(dh) / scale, 1 / scale), display.maxY - rect.minY)
        // Keep the drag's anchor and endpoint at their relative positions in
        // the resized rectangle, including reverse and centre-anchored drags.
        func rebased(_ point: CGPoint, zeroFraction: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (before.width > 0 ? (point.x - before.minX) / before.width : zeroFraction) * rect.width,
                    y: rect.minY + (before.height > 0 ? (point.y - before.minY) / before.height : zeroFraction) * rect.height)
        }
        if let point = anchor { anchor = rebased(point, zeroFraction: 0) }
        if let point = endpoint {
            let next = rebased(point, zeroFraction: 1)
            let dx = next.x - point.x, dy = next.y - point.y
            endpoint = next
            pointerOffset.x += dx
            pointerOffset.y += dy
            if let origin = shiftOrigin { shiftOrigin = CGPoint(x: origin.x + dx, y: origin.y + dy) }
        }
        if let origin = spaceOrigin {
            spaceOrigin = (origin.point, CGRect(origin: origin.rect.origin, size: rect.size))
        }
    }

    private mutating func translate(dx: CGFloat, dy: CGFloat) {
        let dx = min(max(dx, display.minX - rect.minX), display.maxX - rect.maxX)
        let dy = min(max(dy, display.minY - rect.minY), display.maxY - rect.maxY)
        rect = rect.offsetBy(dx: dx, dy: dy)
        if let point = anchor { anchor = CGPoint(x: point.x + dx, y: point.y + dy) }
        if let point = endpoint { endpoint = CGPoint(x: point.x + dx, y: point.y + dy) }
        if let point = shiftOrigin { shiftOrigin = CGPoint(x: point.x + dx, y: point.y + dy) }
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(display.minX + ((point.x - display.minX) * scale).rounded() / scale,
                           display.minX), display.maxX),
                y: min(max(display.minY + ((point.y - display.minY) * scale).rounded() / scale,
                           display.minY), display.maxY))
    }
}
