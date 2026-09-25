import Foundation

public enum DiagnosticEventName: String, Codable, Sendable {
    case historyRecovered, historyRecoveryFailed, historyImageMissing
    case capturePending, captureFailed, captureDiscarded, captureFinalized, finalizationFailed, deliverySucceeded, deliveryFailed, commandRejected
    case noTextFound
}

public enum DiagnosticOperation: String, Codable, Sendable { case capture, copy, retryCopy, save, retrySave, discard, dismiss, launchRecovery, drag, done, deleteHistory, copyRecognizedText }
public enum DiagnosticErrorDomain: String, Codable, Sendable { case captureSource, clipboard, lifecycle, history, fileExport, drag }
public enum DiagnosticErrorCode: String, Codable, Sendable {
    case rootLocked, missingHistoryImage
    case unavailable, emptyImage, cancelled, unknownCapture, duplicateCapture, staleRevision, alreadyDelivered
    case retryNotAvailable, retryRequired, discardedCapture, pendingByteBudgetExceeded, commandInProgress
    case invalidByteAllowance, alreadyFinalized, unknownMigrations, invalidImage, recoveryRequired, insideHistory, unwritable
    case permissionRequired, thumbnailExitNotDue, dragOperationRefused, editingUnavailable, recognitionUnavailable
    case captureExceedsHistoryLimit, pixelCap, memoryBudget, rejectedAlignment
    case noCapturableWindow, windowChanged, windowTooLarge, windowRefused
}

public struct DiagnosticError: Equatable, Codable, Sendable {
    public let domain: DiagnosticErrorDomain
    public let code: DiagnosticErrorCode
    public init(domain: DiagnosticErrorDomain, code: DiagnosticErrorCode) {
        self.domain = domain
        self.code = code
    }
}

/// The only allowed field is a closed operation value. No strings, identifiers or payloads.
public struct DiagnosticEvent: Equatable, Codable, Sendable {
    public let name: DiagnosticEventName
    public let operation: DiagnosticOperation
    public let error: DiagnosticError?
    public init(name: DiagnosticEventName, operation: DiagnosticOperation, error: DiagnosticError? = nil) {
        self.name = name
        self.operation = operation
        self.error = error
    }
}

public protocol DiagnosticSink: Sendable {
    func record(_ event: DiagnosticEvent) async
}

public struct DiagnosticRecord: Equatable, Codable, Sendable {
    public let recordedAt: Date
    public let event: DiagnosticEvent
}

/// Local, in-memory diagnostics. No filesystem or system-log adapter is installed by the core.
public actor LocalDiagnosticLog: DiagnosticSink {
    private let clock: @Sendable () -> Date
    private var records: [DiagnosticRecord] = []

    public init(clock: @escaping @Sendable () -> Date = { Date() }) { self.clock = clock }

    public func record(_ event: DiagnosticEvent) {
        let now = clock()
        expire(at: now)
        records.append(DiagnosticRecord(recordedAt: now, event: event))
    }

    public func entries() -> [DiagnosticRecord] {
        expire(at: clock())
        return records
    }

    private func expire(at now: Date) {
        let cutoff = now.addingTimeInterval(-604_800)
        records.removeAll { $0.recordedAt <= cutoff }
    }
}

extension DiagnosticEvent {
    init(command: CaptureCommand, outcome: CaptureCommandOutcome) {
        let operation: DiagnosticOperation
        switch command {
        case .capture, .captureFullScreen, .captureWindow, .captureScrolling: operation = .capture
        case .copy: operation = .copy
        case .retryCopy: operation = .retryCopy
        case .save: operation = .save
        case .retrySave: operation = .retrySave
        case .discard: operation = .discard
        case .dismiss: operation = .dismiss
        case let .exitThumbnail(_, exit):
            switch exit.outcome {
            case .finalizeToHistory: operation = .dismiss
            case .discard: operation = .discard
            }
        case .drag: operation = .drag
        case .done, .render: operation = .done
        case .deleteHistory: operation = .deleteHistory
        case .copyRecognizedText: operation = .copyRecognizedText
        }
        let name: DiagnosticEventName
        let error: DiagnosticError?
        switch outcome {
        case .edited(_, _, .some), .rendered(_, .some):
            name = .deliveryFailed
            error = DiagnosticError(domain: .clipboard, code: .unavailable)
        case .rendered(_, nil):
            name = .capturePending
            error = nil
        case let .finalized(_, commit), let .edited(_, commit, _):
            switch commit {
            case .committed:
                name = .captureFinalized
                error = nil
            case let .notCommitted(reason):
                name = .finalizationFailed
                switch reason {
                case .historyUnavailable: error = DiagnosticError(domain: .history, code: .unavailable)
                case .unknownMigrations: error = DiagnosticError(domain: .history, code: .unknownMigrations)
                case .invalidImage: error = DiagnosticError(domain: .history, code: .invalidImage)
                case .recoveryRequired: error = DiagnosticError(domain: .history, code: .recoveryRequired)
                case .captureExceedsHistoryLimit: error = DiagnosticError(domain: .history, code: .captureExceedsHistoryLimit)
                }
            }
        case .pending:
            name = .capturePending
            error = nil
        case let .scrollingLimited(_, notice):
            name = .capturePending
            error = DiagnosticError(domain: .captureSource, code: notice == .pixelCap ? .pixelCap : .memoryBudget)
        case let .scrollingRefused(notice):
            name = .captureFailed
            error = DiagnosticError(domain: .captureSource, code: notice == .pixelCap ? .pixelCap : .memoryBudget)
        case .discarded:
            name = .captureDiscarded
            error = nil
        case .historyDeleted:
            name = .captureDiscarded
            error = nil
        case .noTextFound:
            name = .noTextFound
            error = nil
        case .permissionRequired:
            name = .captureFailed
            error = DiagnosticError(domain: .captureSource, code: .permissionRequired)
        case let .captureFailed(failure):
            name = .captureFailed
            switch failure {
            case .rejectedAlignment: error = DiagnosticError(domain: .captureSource, code: .rejectedAlignment)
            case .unavailable: error = DiagnosticError(domain: .captureSource, code: .unavailable)
            case .cancelled: error = DiagnosticError(domain: .captureSource, code: .cancelled)
            case .emptyImage: error = DiagnosticError(domain: .captureSource, code: .emptyImage)
            case .permissionRequired: error = DiagnosticError(domain: .captureSource, code: .permissionRequired)
            case .window(.noWindow): error = DiagnosticError(domain: .captureSource, code: .noCapturableWindow)
            case .window(.windowChanged): error = DiagnosticError(domain: .captureSource, code: .windowChanged)
            case .window(.tooLarge): error = DiagnosticError(domain: .captureSource, code: .windowTooLarge)
            case .window(.systemRefused): error = DiagnosticError(domain: .captureSource, code: .windowRefused)
            }
        case let .drag(result):
            switch result.delivery {
            case .copied:
                name = .deliverySucceeded
                switch result.commit {
                case .committed, nil: error = nil
                case .notCommitted(.historyUnavailable): error = DiagnosticError(domain: .history, code: .unavailable)
                case .notCommitted(.unknownMigrations): error = DiagnosticError(domain: .history, code: .unknownMigrations)
                case .notCommitted(.invalidImage): error = DiagnosticError(domain: .history, code: .invalidImage)
                case .notCommitted(.recoveryRequired): error = DiagnosticError(domain: .history, code: .recoveryRequired)
                case .notCommitted(.captureExceedsHistoryLimit): error = DiagnosticError(domain: .history, code: .captureExceedsHistoryLimit)
                }
            case .failed:
                name = .deliveryFailed
                error = DiagnosticError(domain: .drag, code: .unavailable)
            }
        case let .copy(result):
            switch result.delivery {
            case .copied:
                name = .deliverySucceeded
                switch result.commit {
                case .committed: error = nil
                case .notCommitted(.historyUnavailable): error = DiagnosticError(domain: .history, code: .unavailable)
                case .notCommitted(.unknownMigrations): error = DiagnosticError(domain: .history, code: .unknownMigrations)
                case .notCommitted(.invalidImage): error = DiagnosticError(domain: .history, code: .invalidImage)
                case .notCommitted(.recoveryRequired): error = DiagnosticError(domain: .history, code: .recoveryRequired)
                case .notCommitted(.captureExceedsHistoryLimit): error = DiagnosticError(domain: .history, code: .captureExceedsHistoryLimit)
                }
            case .failed:
                name = .deliveryFailed
                error = DiagnosticError(domain: .clipboard, code: .unavailable)
            }
        case let .save(result):
            switch result.delivery {
            case .saved:
                name = .deliverySucceeded
                switch result.commit {
                case .committed: error = nil
                case .notCommitted(.historyUnavailable): error = DiagnosticError(domain: .history, code: .unavailable)
                case .notCommitted(.unknownMigrations): error = DiagnosticError(domain: .history, code: .unknownMigrations)
                case .notCommitted(.invalidImage): error = DiagnosticError(domain: .history, code: .invalidImage)
                case .notCommitted(.recoveryRequired): error = DiagnosticError(domain: .history, code: .recoveryRequired)
                case .notCommitted(.captureExceedsHistoryLimit): error = DiagnosticError(domain: .history, code: .captureExceedsHistoryLimit)
                }
            case let .failed(failure):
                name = .deliveryFailed
                switch failure {
                case .unavailable: error = DiagnosticError(domain: .fileExport, code: .unavailable)
                case .insideHistory: error = DiagnosticError(domain: .fileExport, code: .insideHistory)
                case .unwritable: error = DiagnosticError(domain: .fileExport, code: .unwritable)
                }
            }
        case let .recognizedText(result):
            switch result.delivery {
            case .copied:
                name = .deliverySucceeded
                error = nil
            case .failed:
                name = .deliveryFailed
                error = DiagnosticError(domain: .clipboard, code: .unavailable)
            }
        case let .rejected(reason):
            name = .commandRejected
            let code: DiagnosticErrorCode
            switch reason {
            case .unknownCapture: code = .unknownCapture
            case .duplicateCapture: code = .duplicateCapture
            case .staleRevision: code = .staleRevision
            case .alreadyDelivered: code = .alreadyDelivered
            case .alreadyFinalized: code = .alreadyFinalized
            case .retryNotAvailable: code = .retryNotAvailable
            case .retryRequired: code = .retryRequired
            case .discardedCapture: code = .discardedCapture
            case .pendingByteBudgetExceeded: code = .pendingByteBudgetExceeded
            case .commandInProgress: code = .commandInProgress
            case .invalidByteAllowance: code = .invalidByteAllowance
            case .thumbnailExitNotDue: code = .thumbnailExitNotDue
            case .dragOperationRefused: code = .dragOperationRefused
            case .editingUnavailable: code = .editingUnavailable
            case .recognitionUnavailable: code = .recognitionUnavailable
            }
            error = DiagnosticError(domain: .lifecycle, code: code)
        }
        self.init(name: name, operation: operation, error: error)
    }
}
