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
