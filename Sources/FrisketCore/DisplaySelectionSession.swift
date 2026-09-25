import Foundation

/// One display in AppKit global, bottom-left-origin points. IDs must be unique;
/// frames/scales obey SelectionGeometry's finite, positive, pixel-size contract.
public struct SelectionDisplay: Equatable, Sendable {
    public let id: UInt32
    public let frame: CGRect
    public let scale: CGFloat

    public init(id: UInt32, frame: CGRect, scale: CGFloat) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }
}

/// Pure multi-display policy; pixel snapping and modifiers stay in SelectionGeometry.
public struct DisplaySelectionSession: Sendable {
    private let displays: [SelectionDisplay]
    public private(set) var originDisplay: SelectionDisplay?
    private var geometry: SelectionGeometry?
    private var locked = false
    public private(set) var isCancelled = false
    public var rect: CGRect? { geometry?.rect }
    public var acceptedRect: CGRect? {
        guard let rect, let originDisplay,
              rect.width >= 1 / originDisplay.scale, rect.height >= 1 / originDisplay.scale else { return nil }
        return rect
    }

    public init(displays: [SelectionDisplay], pointer: CGPoint) {
        self.displays = displays.sorted { $0.id < $1.id }
        originDisplay = display(at: pointer)
        if let originDisplay {
            geometry = SelectionGeometry(displayFrame: originDisplay.frame, scale: originDisplay.scale)
        }
    }

    /// AppKit's `NSMouseInRect` rule for unflipped screens: x in [minX, maxX), y in (minY, maxY].
    /// The pointer's y runs from minY + 1 on the bottom row to maxY on the top row, so every pixel,
    /// including the top row, has exactly one owner (D14). Mirrored displays use the lowest ID.
    public func display(at point: CGPoint) -> SelectionDisplay? {
        displays.first {
            point.x >= $0.frame.minX && point.x < $0.frame.maxX
                && point.y > $0.frame.minY && point.y <= $0.frame.maxY
        }
    }

    /// The first drag selects the origin, which may differ from the invocation
    /// display. Later drags may restart only on that same display.
    @discardableResult public mutating func begin(at point: CGPoint) -> Bool {
        guard !isCancelled, let owner = display(at: point), !locked || owner == originDisplay else { return false }
        originDisplay = owner
        geometry = SelectionGeometry(displayFrame: owner.frame, scale: owner.scale)
        geometry?.begin(at: point)
        locked = true
        return true
    }

    public mutating func update(to point: CGPoint, modifiers: SelectionGeometry.Modifiers = []) {
        geometry?.update(to: point, modifiers: modifiers)
    }

    public mutating func nudge(dx: Int, dy: Int) { geometry?.nudge(dx: dx, dy: dy) }
    public mutating func resize(dw: Int, dh: Int) { geometry?.resize(dw: dw, dh: dh) }

    /// A stale layout cannot safely describe the preview or final capture.
    /// Ignore enumeration order, but cancel irreversibly on any actual change.
    public mutating func updateDisplays(_ current: [SelectionDisplay]) {
        guard current.sorted(by: { $0.id < $1.id }) != displays else { return }
        isCancelled = true
        originDisplay = nil
        geometry = nil
    }
}
