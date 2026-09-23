import Foundation

/// Window metadata only; frames and pointer positions use global, top-left-origin
/// screen points. Input order is front to back, independent of window identifiers.
public struct WindowCandidate: Equatable, Sendable {
    public let id: UInt32
    public let ownerProcessID: Int32
    public let bundleIdentifier: String?
    public let frame: CGRect
    public let layer: Int
    public let isOnScreen: Bool
    public let isMinimized: Bool

    public init(id: UInt32, ownerProcessID: Int32, bundleIdentifier: String?, frame: CGRect,
                layer: Int, isOnScreen: Bool, isMinimized: Bool) {
        self.id = id
        self.ownerProcessID = ownerProcessID
        self.bundleIdentifier = bundleIdentifier
        self.frame = frame
        self.layer = layer
        self.isOnScreen = isOnScreen
        self.isMinimized = isMinimized
    }
}

/// Pure selection policy shared by the live overlay and fixture capture source.
public struct WindowSelection: Sendable {
    public let candidates: [WindowCandidate]

    public init(windows: [WindowCandidate], ownProcessID: Int32, ownBundleIdentifier: String) {
        candidates = windows.filter { window in
            window.isOnScreen && !window.isMinimized && window.layer == 0
                && window.ownerProcessID != ownProcessID
                && window.bundleIdentifier != nil && window.bundleIdentifier != ownBundleIdentifier
                && window.frame.origin.x.isFinite && window.frame.origin.y.isFinite
                && window.frame.width.isFinite && window.frame.height.isFinite
                && window.frame.width > 0 && window.frame.height > 0
        }
    }

    public func window(at point: CGPoint) -> WindowCandidate? {
        candidates.first { $0.frame.contains(point) }
    }
}
