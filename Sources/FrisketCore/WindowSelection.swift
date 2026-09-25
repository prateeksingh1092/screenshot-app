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
    /// `kCGDockWindowLevel`. The Dock, pop-up menus, the menu bar and the cursor sit at or above it.
    public static let dockLevel = 20
    /// Helper windows smaller than this on a side are never a capture target.
    public static let minimumSide: CGFloat = 32
    public static let dockBundleIdentifier = "com.apple.dock"

    public let candidates: [WindowCandidate]

    public init(windows: [WindowCandidate], ownProcessID: Int32, ownBundleIdentifier: String) {
        // The platform excludes desktop elements. Exclude Frisket by identity, and system
        // chrome by level, owner and size (D2): foreign floating windows below the Dock
        // level remain valid candidates.
        candidates = windows.filter { window in
            guard let bundle = window.bundleIdentifier, !bundle.isEmpty else { return false }
            return window.isOnScreen && !window.isMinimized
                && window.ownerProcessID != ownProcessID
                && bundle != ownBundleIdentifier && bundle != Self.dockBundleIdentifier
                && window.layer < Self.dockLevel
                && window.frame.origin.x.isFinite && window.frame.origin.y.isFinite
                && window.frame.width.isFinite && window.frame.height.isFinite
                && window.frame.width >= Self.minimumSide && window.frame.height >= Self.minimumSide
        }
    }

    public func window(at point: CGPoint) -> WindowCandidate? {
        candidates.first { $0.frame.contains(point) }
    }
}
