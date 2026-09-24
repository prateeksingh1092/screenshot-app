import Foundation

/// Named byte limits for one Frisket session.
///
/// Encoded fields are reservations against `pendingSessionEncodedBytes`.
/// `scrollingMemoryBytes` is the process peak for retained scrolling strips.
/// It is not an encoded reservation and is not combined with one.
public struct CaptureBudgets: Equatable, Sendable {
    public let pendingSessionEncodedBytes: Int
    public let stillEncodedBytes: Int
    public let stillDecodedBytes: Int
    public let scrollingEncodedBytes: Int
    public let scrollingMemoryBytes: Int
    public let scrollingPixelCap: Int

    public init(pendingSessionEncodedBytes: Int, stillEncodedBytes: Int, stillDecodedBytes: Int,
                scrollingEncodedBytes: Int, scrollingMemoryBytes: Int, scrollingPixelCap: Int) {
        self.pendingSessionEncodedBytes = pendingSessionEncodedBytes
        self.stillEncodedBytes = stillEncodedBytes
        self.stillDecodedBytes = stillDecodedBytes
        self.scrollingEncodedBytes = scrollingEncodedBytes
        self.scrollingMemoryBytes = scrollingMemoryBytes
        self.scrollingPixelCap = scrollingPixelCap
    }

    /// 16 GB machine. One capture reserves 128 MB inside a 256 MB pending session.
    /// Scrolling may use a 2 GB working set while that image is assembled.
    public static let v1 = CaptureBudgets(
        pendingSessionEncodedBytes: 256 * 1024 * 1024,
        stillEncodedBytes: 128 * 1024 * 1024,
        stillDecodedBytes: 128 * 1024 * 1024,
        scrollingEncodedBytes: 128 * 1024 * 1024,
        scrollingMemoryBytes: 2_000_000_000,
        scrollingPixelCap: 5_120 * 57_600)
}
