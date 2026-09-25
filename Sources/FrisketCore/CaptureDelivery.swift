import Foundation

/// Encoded PNG bytes supplied by the capture adapter; no file location or text payload.
public struct CaptureImage: Sendable {
    public let pngData: Data
    public init(pngData: Data) { self.pngData = pngData }
}

public enum CaptureSourceFailure: Error, Equatable, Sendable {
    case unavailable, emptyImage, cancelled
    case rejectedAlignment(ScrollingCaptureAlignment)
    case permissionRequired(CapturePermissionState)
}

/// The source must bound its work to the allowance and return encoded PNG data.
public protocol CapturePixelSource: Sendable {
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure>
}

public struct ClipboardImage: Equatable, Sendable {
    public let pngData: Data
    public let currentHostOnly = true
    public let concealed = true
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
