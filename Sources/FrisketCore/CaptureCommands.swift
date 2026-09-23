import Foundation

public struct CaptureID: Hashable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct CaptureRevision: Hashable, Sendable {
    public let captureID: CaptureID
    public let number: UInt64
    public init(captureID: CaptureID, number: UInt64) {
        self.captureID = captureID
        self.number = number
    }
}

public enum CaptureCommand: Sendable {
    case capture(CaptureID, maximumBytes: Int)
    case captureFullScreen(CaptureID, maximumBytes: Int)
    case copy(CaptureRevision)
    case retryCopy(CaptureRevision)
    case dismiss(CaptureRevision)
    case discard(CaptureID)
    case drag(CaptureRevision, DragFileOperation)
}

public enum CommitOutcome: Equatable, Sendable {
    case committed
    case notCommitted(CommitUnavailableReason)
}

public enum CommitUnavailableReason: Sendable { case historyUnavailable, unknownMigrations, invalidImage, recoveryRequired }

public enum DeliveryOutcome: Equatable, Sendable {
    case copied(ClipboardReceipt)
    case failed(ClipboardFailure)
}

public struct CopyOutcome: Equatable, Sendable {
    public let revision: CaptureRevision
    public let commit: CommitOutcome
    public let delivery: DeliveryOutcome
    public init(revision: CaptureRevision, commit: CommitOutcome, delivery: DeliveryOutcome) {
        self.revision = revision
        self.commit = commit
        self.delivery = delivery
    }
}

public struct DragOutcome: Equatable, Sendable {
    public let revision: CaptureRevision
    public let commit: CommitOutcome
    public let delivery: DragDelivery
    public init(revision: CaptureRevision, commit: CommitOutcome, delivery: DragDelivery) {
        self.revision = revision
        self.commit = commit
        self.delivery = delivery
    }
}

public enum CommandRejection: Equatable, Sendable { case unknownCapture, duplicateCapture, staleRevision, alreadyDelivered, alreadyFinalized, retryNotAvailable, retryRequired, discardedCapture, pendingByteBudgetExceeded, commandInProgress, invalidByteAllowance, dragOperationRefused }

public enum CaptureCommandOutcome: Equatable, Sendable {
    case pending(CaptureRevision)
    case discarded(CaptureID)
    case copy(CopyOutcome)
    case finalized(CaptureRevision, CommitOutcome)
    case drag(DragOutcome)
    case captureFailed(CaptureSourceFailure)
    case permissionRequired(CapturePermissionState)
    case rejected(CommandRejection)
}

/// The sole action interface. The coordinator owns lifecycle policy and memory.
public struct CaptureCommandLayer: Sendable {
    private let diagnostics: any DiagnosticSink
    private let coordinator: CaptureLifecycleCoordinator

    public init(permission: any CapturePermissionSource, source: any CapturePixelSource, fullScreenSource: (any CapturePixelSource)? = nil,
                clipboard: any ImageClipboard, pendingByteLimit: Int,
                diagnostics: any DiagnosticSink = LocalDiagnosticLog(), history: (any CaptureHistory)? = nil,
                drag: (any DragHandoff)? = nil, dragStaging: (any DragCopyStaging)? = nil) {
        self.diagnostics = diagnostics
        coordinator = CaptureLifecycleCoordinator(permission: permission, source: source, fullScreenSource: fullScreenSource, clipboard: clipboard,
                                                  pendingByteLimit: pendingByteLimit, history: history, drag: drag, dragStaging: dragStaging)
    }

    public func historyEntries() async -> Result<[HistoryEntry], HistoryFailure> {
        await coordinator.historyEntries()
    }

    /// Read-only presentation query; the coordinator remains the owner of pending bytes.
    public func image(for revision: CaptureRevision) async -> CaptureImage? {
        await coordinator.image(for: revision)
    }

    public func execute(_ command: CaptureCommand) async -> CaptureCommandOutcome {
        let outcome = await coordinator.execute(command)
        await diagnostics.record(DiagnosticEvent(command: command, outcome: outcome))
        return outcome
    }
}
