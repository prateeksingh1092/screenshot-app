import Foundation

/// Named byte limits for one Frisket session.
///
/// Encoded fields are reservations against `pendingSessionEncodedBytes`.
public struct CaptureBudgets: Equatable, Sendable {
    public let pendingSessionEncodedBytes: Int
    public let stillEncodedBytes: Int
    public let stillDecodedBytes: Int

    public init(pendingSessionEncodedBytes: Int, stillEncodedBytes: Int, stillDecodedBytes: Int) {
        self.pendingSessionEncodedBytes = pendingSessionEncodedBytes
        self.stillEncodedBytes = stillEncodedBytes
        self.stillDecodedBytes = stillDecodedBytes
    }

    /// 16 GB machine. One capture reserves 128 MB inside a 256 MB pending session.
    public static let v1 = CaptureBudgets(
        pendingSessionEncodedBytes: 256 * 1024 * 1024,
        stillEncodedBytes: 128 * 1024 * 1024,
        stillDecodedBytes: 128 * 1024 * 1024)
}
