import Darwin
import Foundation
import FrisketCore

/// Opt-in numeric instrumentation. No image, identifier, path or error payloads.
/// One instance per app process; the app serializes captures on the main actor.
@MainActor final class CaptureLatencyLog {
    private var recorder: CaptureLatencyRecorder
    private var enabled: Bool
    private let write: (Data) throws -> Void

    init(enabled: Bool, clock: @escaping @Sendable () -> UInt64,
         write: @escaping (Data) throws -> Void) {
        self.enabled = enabled
        self.recorder = CaptureLatencyRecorder(clock: clock)
        self.write = write
    }

    static func standardOutput() -> CaptureLatencyLog {
        CaptureLatencyLog(enabled: ProcessInfo.processInfo.environment["FRISKET_CAPTURE_LATENCY"] == "1",
            clock: { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) },
            write: { try FileHandle.standardOutput.write(contentsOf: $0) })
    }

    func selectionAccepted() {
        guard enabled else { return }
        recorder.selectionAccepted()
    }

    func cancel() { recorder.cancel() }

    func thumbnailSubmitted() {
        guard enabled, let row = recorder.thumbnailSubmitted() else { return }
        do { try write(Data(row.utf8)) }
        catch { enabled = false } // Fail closed: incomplete sessions cannot become reports.
    }
}
