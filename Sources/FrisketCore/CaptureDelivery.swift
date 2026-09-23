import Foundation

/// Encoded PNG bytes supplied by the capture adapter; no file location or text payload.
public struct CaptureImage: Sendable {
    public let pngData: Data
    public init(pngData: Data) { self.pngData = pngData }
}

public enum CaptureSourceFailure: Error, Equatable, Sendable {
    case unavailable, emptyImage, cancelled
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
    public init(pngData: Data) { self.pngData = pngData }
}

public struct ClipboardReceipt: Equatable, Sendable {
    public let changeCount: Int
    public init(changeCount: Int) { self.changeCount = changeCount }
}

public enum ClipboardFailure: Error, Equatable, Sendable { case unavailable }

/// Write only. Adapters must honor both privacy flags and return the write's change count.
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

/// The drag session reports these in either order. The staging file stays until both have run.
public protocol DragCopyEvents: Sendable {
    func promiseWriteReturned() async throws
    func dragSessionEnded() async
}

/// Recording stand-ins and the file-promise adapter sit here. Only `.copy` is a handoff.
public protocol DragHandoff: Sendable {
    func deliver(_ operation: DragFileOperation, image: DragImage, events: any DragCopyEvents) async throws -> DragDelivery
}

public struct DragStagingID: Hashable, Sendable {
    let rawValue: UUID
    init(rawValue: UUID) { self.rawValue = rawValue }
}

/// Disk lifetime of one drag copy. Callers learn only when to stage and when each event happened.
public protocol DragCopyStaging: Sendable {
    func stage(_ request: AuthorizedFinalization) async throws -> DragStagingID
    func promiseWriteReturned(_ id: DragStagingID) async throws
    func dragSessionEnded(_ id: DragStagingID) async
}
