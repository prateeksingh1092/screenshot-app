import Foundation

/// Pairs the two app-logged latency events of the ticket 37 interface into
/// numbered rows. Both events read the one injected monotonic nanosecond clock.
public struct CaptureLatencyRecorder: Sendable {
    private let clock: @Sendable () -> UInt64
    private var start: UInt64?
    private var run = 0

    public init(clock: @escaping @Sendable () -> UInt64) { self.clock = clock }

    public mutating func selectionAccepted() { start = clock() }

    public mutating func cancel() { start = nil }

    /// The newline-terminated JSON row `{"run":…,"start_ns":…,"end_ns":…}`.
    public mutating func thumbnailSubmitted() -> String? {
        let end = clock()
        guard let start else { return nil }
        self.start = nil
        run += 1
        return "{\"run\":\(run),\"start_ns\":\(start),\"end_ns\":\(end)}\n"
    }
}
