import Foundation
import FrisketCore
@testable import FrisketAdapters
import Testing

@Suite @MainActor struct CaptureLatencyLogTests {
    @Test func loggingIsOptInAndEmitsOnlyThePairedNumericRow() {
        var output: [Data] = []
        let disabled = CaptureLatencyLog(enabled: false, clock: { 10 }, write: { output.append($0) })
        disabled.selectionAccepted()
        disabled.thumbnailSubmitted()
        #expect(output.isEmpty)
        let enabled = CaptureLatencyLog(enabled: true, clock: { 20 }, write: { output.append($0) })
        enabled.selectionAccepted()
        enabled.thumbnailSubmitted()
        enabled.thumbnailSubmitted()
        #expect(output == [Data("{\"run\":1,\"start_ns\":20,\"end_ns\":20}\n".utf8)])
    }
}
