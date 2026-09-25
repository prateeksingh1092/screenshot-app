import FrisketCore
@testable import FrisketAdapters
import Testing

/// Decision 25 through the unified log (ticket 80): only closed names and codes reach a message,
/// so the message may be marked public; Frisket writes no log file of its own.
@Suite struct SystemDiagnosticLogTests {
    @Test func messageCarriesOnlyTheClosedEventValues() {
        let failed = DiagnosticEvent(name: .deliveryFailed, operation: .save,
                                     error: DiagnosticError(domain: .fileExport, code: .unwritable))
        #expect(SystemDiagnosticLog.message(for: failed) == "deliveryFailed save fileExport.unwritable")
        #expect(SystemDiagnosticLog.message(for: DiagnosticEvent(name: .historyRecovered, operation: .launchRecovery))
                == "historyRecovered launchRecovery")
    }

    @Test func recordingDoesNotThrowOrBlock() async {
        let log = SystemDiagnosticLog(subsystem: "app.frisket.tests")
        await log.record(DiagnosticEvent(name: .capturePending, operation: .capture))
        await log.record(DiagnosticEvent(name: .captureFailed, operation: .capture,
                                         error: DiagnosticError(domain: .captureSource, code: .cancelled)))
    }
}
