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

/// One entry of the window server's on-screen list, front to back. Metadata only; it supplies the order.
public struct WindowListRow: Equatable, Sendable {
    public let id: UInt32
    public let ownerProcessID: Int32?
    public let layer: Int?
    public let isOnScreen: Bool

    public init(id: UInt32, ownerProcessID: Int32?, layer: Int?, isOnScreen: Bool) {
        self.id = id
        self.ownerProcessID = ownerProcessID
        self.layer = layer
        self.isOnScreen = isOnScreen
    }
}

/// One window ScreenCaptureKit can share. It is authoritative for shareability, never for order.
/// The owner fields are nil when ScreenCaptureKit names no owning app.
public struct ShareableWindowRow: Equatable, Sendable {
    public let id: UInt32
    public let ownerProcessID: Int32?
    public let bundleIdentifier: String?
    public let frame: CGRect
    public let layer: Int
    public let isOnScreen: Bool

    public init(id: UInt32, ownerProcessID: Int32?, bundleIdentifier: String?, frame: CGRect,
                layer: Int, isOnScreen: Bool) {
        self.id = id
        self.ownerProcessID = ownerProcessID
        self.bundleIdentifier = bundleIdentifier
        self.frame = frame
        self.layer = layer
        self.isOnScreen = isOnScreen
    }
}

/// Both window listings, as fetched together.
public struct WindowRows: Equatable, Sendable {
    public let ordered: [WindowListRow]
    public let shareable: [ShareableWindowRow]

    public init(ordered: [WindowListRow], shareable: [ShareableWindowRow]) {
        self.ordered = ordered
        self.shareable = shareable
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

    /// Joins the listings by window ID and filters the result (ticket 75). A window is a candidate only
    /// when both listings name the same owner and layer, it is on screen in both, and its app is not on
    /// the Capture exclusion list. Public ScreenCaptureKit has no minimized flag, so a window missing
    /// from either on-screen listing counts as minimized.
    public init(rows: WindowRows, excluding exclusions: Set<String>, ownProcessID: Int32, ownBundleIdentifier: String) {
        let byID = Dictionary(rows.shareable.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let joined = rows.ordered.compactMap { listed -> WindowCandidate? in
            guard let window = byID[listed.id], let owner = window.ownerProcessID,
                  let bundle = window.bundleIdentifier, !exclusions.contains(bundle),
                  listed.ownerProcessID == owner, listed.layer == window.layer else { return nil }
            let onScreen = window.isOnScreen && listed.isOnScreen
            return WindowCandidate(id: listed.id, ownerProcessID: owner, bundleIdentifier: bundle,
                frame: window.frame, layer: window.layer, isOnScreen: onScreen, isMinimized: !onScreen)
        }
        self.init(windows: joined, ownProcessID: ownProcessID, ownBundleIdentifier: ownBundleIdentifier)
    }

    public init(windows: [WindowCandidate], ownProcessID: Int32, ownBundleIdentifier: String) {
        // The platform excludes desktop elements. Exclude Frisket by identity, and system
        // chrome by level, owner and size (D2): foreign floating windows below the Dock
        // level remain valid candidates. The cursor is excluded by its level (2147483630,
        // `kCGCursorWindowLevel`) and its size, not by its owner's empty bundle ID: apps
        // without a bundle ID own real windows too (ticket 89).
        candidates = windows.filter { window in
            let bundle = window.bundleIdentifier
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
