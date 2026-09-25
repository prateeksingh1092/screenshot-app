import Foundation

/// Encoded PNG bytes supplied by the capture adapter; no file location or text payload.
public struct CaptureImage: Sendable {
    public let pngData: Data
    /// The display the pixels came from, where the Thumbnail appears. Nil when unknown.
    public let displayID: UInt32?
    public init(pngData: Data, displayID: UInt32? = nil) {
        self.pngData = pngData
        self.displayID = displayID
    }
}

public enum CaptureSourceFailure: Error, Equatable, Sendable {
    case unavailable, emptyImage, cancelled
    case permissionRequired(CapturePermissionState)
    case window(WindowCaptureFailure)
}

/// Why a window capture failed. Each case names its own cause (D2, story 84).
public enum WindowCaptureFailure: Equatable, Sendable, CaseIterable {
    /// No on-screen window can be captured once Frisket, system chrome, minimized
    /// windows and the Capture exclusion list are left out.
    case noWindow
    /// The chosen window closed, moved to another Space or changed before its pixels were taken.
    case windowChanged
    /// The window has more pixels than one capture may hold.
    case tooLarge
    /// macOS did not return the window's pixels.
    case systemRefused

    public var title: String { "Window not captured" }

    public var message: String {
        switch self {
        case .noWindow:
            return "There is no window Frisket can capture. It leaves out its own windows, minimized windows, the Dock, menus and apps on the Capture exclusion list."
        case .windowChanged:
            return "The window closed, moved to another Space or changed before Frisket could capture it. Try again."
        case .tooLarge:
            return "This window is too large to capture. Make the window smaller and try again."
        case .systemRefused:
            return "macOS did not return the window's pixels. Try again, or capture an area instead."
        }
    }
}

/// The source must bound its work to the allowance and return encoded PNG data.
public protocol CapturePixelSource: Sendable {
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure>
}

/// The pasteboard adapter marks every write concealed and current-host-only (`AreaCaptureCommandsTests`).
public struct ClipboardImage: Equatable, Sendable {
    public let pngData: Data
    /// Metadata-only guard for replacing this app's earlier copy. Nil means an explicit Copy.
    public let replacing: ClipboardReceipt?
    public init(pngData: Data, replacing: ClipboardReceipt? = nil) {
        self.pngData = pngData
        self.replacing = replacing
    }
}

public struct ClipboardReceipt: Equatable, Sendable {
    public let changeCount: Int
    public init(changeCount: Int) { self.changeCount = changeCount }
}

public enum ClipboardFailure: Error, Equatable, Sendable { case unavailable, changed }

/// Write only. Adapters must honor the privacy flags and conditional replacement receipt,
/// comparing change-count metadata immediately before writing without reading clipboard content.
public protocol ImageClipboard: Sendable {
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure>
}

public enum DragFileOperation: Equatable, Sendable {
    case copy, move, delete
}

public struct DragImage: Equatable, Sendable {
    public let pngData: Data
    public init(pngData: Data) { self.pngData = pngData }
}

public enum DragDelivery: Equatable, Sendable {
    case copied, failed
}

/// The drag session reports these in either order. Nothing is staged on disk: the promised
/// file is written from memory, and a drag finalizes only once the destination accepted it (DA-3).
public protocol DragCopyEvents: Sendable {
    func promiseWriteReturned() async throws
    func dragSessionEnded() async
}

/// Recording stand-ins and the file-promise adapter sit here. Only `.copy` is a handoff.
public protocol DragHandoff: Sendable {
    func deliver(_ operation: DragFileOperation, image: DragImage, events: any DragCopyEvents) async throws -> DragDelivery
}
