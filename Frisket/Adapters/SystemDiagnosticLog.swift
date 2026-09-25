import FrisketCore
import os

/// Decision 25 through the unified log: the system keeps and expires the entries, and Frisket
/// writes no log file of its own. A message holds only closed enum values (event, operation,
/// error domain and code), never pixels, text, clipboard contents, paths or file names,
/// so it is marked public; nothing else is interpolated.
public struct SystemDiagnosticLog: DiagnosticSink {
    private let logger: Logger

    public init(subsystem: String) {
        logger = Logger(subsystem: subsystem, category: "lifecycle")
    }

    public func record(_ event: DiagnosticEvent) async {
        let message = Self.message(for: event)
        if event.error == nil {
            logger.notice("\(message, privacy: .public)")
        } else {
            logger.error("\(message, privacy: .public)")
        }
    }

    static func message(for event: DiagnosticEvent) -> String {
        var message = "\(event.name.rawValue) \(event.operation.rawValue)"
        if let error = event.error {
            message += " \(error.domain.rawValue).\(error.code.rawValue)"
        }
        return message
    }
}
