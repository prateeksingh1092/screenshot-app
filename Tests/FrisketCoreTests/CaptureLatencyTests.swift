import FrisketCore
import Synchronization
import Testing

private final class ScriptedClock: Sendable {
    private let readings: Mutex<[UInt64]>
    init(_ readings: [UInt64]) { self.readings = Mutex(readings) }
    func read() -> UInt64 { readings.withLock { $0.removeFirst() } }
}

@Suite struct CaptureLatencyTests {
    @Test func abandonedCaptureCannotSupplyTheNextThumbnailsStart() {
        let clock = ScriptedClock([10, 20, 30, 40])
        var recorder = CaptureLatencyRecorder(clock: clock.read)
        recorder.selectionAccepted()
        recorder.cancel()
        #expect(recorder.thumbnailSubmitted() == nil)
        recorder.selectionAccepted()
        #expect(recorder.thumbnailSubmitted() == "{\"run\":1,\"start_ns\":30,\"end_ns\":40}\n")
    }
    @Test func aSubmittedThumbnailCannotBeLoggedTwice() {
        let clock = ScriptedClock([10, 20, 30])
        var recorder = CaptureLatencyRecorder(clock: clock.read)
        recorder.selectionAccepted()
        #expect(recorder.thumbnailSubmitted() != nil)
        #expect(recorder.thumbnailSubmitted() == nil)
    }
    @Test func acceptedSelectionAndSubmittedThumbnailWriteOneNumericRow() {
        let clock = ScriptedClock([1_000_000_000, 1_100_000_000])
        var recorder = CaptureLatencyRecorder(clock: clock.read)
        recorder.selectionAccepted()
        #expect(recorder.thumbnailSubmitted() == "{\"run\":1,\"start_ns\":1000000000,\"end_ns\":1100000000}\n")
    }

    @Test func thumbnailWithoutAnAcceptedSelectionWritesNothingAndKeepsTheRunNumber() {
        let clock = ScriptedClock([5, 7, 9])
        var recorder = CaptureLatencyRecorder(clock: clock.read)
        #expect(recorder.thumbnailSubmitted() == nil)
        recorder.selectionAccepted()
        #expect(recorder.thumbnailSubmitted() == "{\"run\":1,\"start_ns\":7,\"end_ns\":9}\n")
    }
}
