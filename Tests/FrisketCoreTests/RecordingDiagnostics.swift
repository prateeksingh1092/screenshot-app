import FrisketCore

/// Test sink: keeps the closed events the coordinator and History record.
actor RecordingDiagnostics: DiagnosticSink {
    private(set) var events: [DiagnosticEvent] = []
    func record(_ event: DiagnosticEvent) async { events.append(event) }
}
