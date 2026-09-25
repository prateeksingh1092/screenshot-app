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
    case captureWindow(CaptureID, maximumBytes: Int)
    case copy(CaptureRevision)
    case retryCopy(CaptureRevision)
    case save(CaptureRevision)
    case retrySave(CaptureRevision)
    case dismiss(CaptureRevision)
    case discard(CaptureID)
    case exitThumbnail(CaptureRevision, ThumbnailExit)
    case drag(CaptureRevision, DragFileOperation)
    /// Finishes an edit: renders the edits over the current revision and finalizes the result as the next revision.
    case done(CaptureRevision, DocumentEdits)
    /// Renders the edits over the current revision as the next revision and keeps it pending.
    /// An editor drag uses it, because only a drop the destination accepts finalizes a drag (DA-3).
    case render(CaptureRevision, DocumentEdits)
    /// Removes a finalized History item. Pending Delete capture stays `.discard`.
    case deleteHistory(CaptureID)
    /// Copies text recognized from this revision's current image. The text is not stored.
    case copyRecognizedText(CaptureRevision)
}

public enum CommitOutcome: Equatable, Sendable {
    case committed
    case notCommitted(CommitUnavailableReason)
}

public enum CommitUnavailableReason: Sendable { case historyUnavailable, unknownMigrations, invalidImage, recoveryRequired, captureExceedsHistoryLimit }

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
    /// `nil` when nothing was committed: the drop was cancelled or failed before any History commit (DA-3).
    public let commit: CommitOutcome?
    public let delivery: DragDelivery
    public init(revision: CaptureRevision, commit: CommitOutcome?, delivery: DragDelivery) {
        self.revision = revision
        self.commit = commit
        self.delivery = delivery
    }
}

public enum CommandRejection: Equatable, Sendable {
    case unknownCapture, duplicateCapture, staleRevision, alreadyDelivered, alreadyFinalized
    case retryNotAvailable, retryRequired, discardedCapture, pendingByteBudgetExceeded
    case commandInProgress, invalidByteAllowance, thumbnailExitNotDue, dragOperationRefused
    case editingUnavailable, recognitionUnavailable
}

public enum CaptureCommandOutcome: Equatable, Sendable {
    case pending(CaptureRevision)
    case discarded(CaptureID)
    case copy(CopyOutcome)
    case save(SaveOutcome)
    case finalized(CaptureRevision, CommitOutcome)
    case drag(DragOutcome)
    /// The new rendered revision replaced the pending image, whether or not History committed it.
    case edited(CaptureRevision, CommitOutcome, clipboardFailure: ClipboardFailure? = nil)
    /// The new rendered revision replaced the pending image and stays pending; nothing was committed.
    case rendered(CaptureRevision, clipboardFailure: ClipboardFailure? = nil)
    case captureFailed(CaptureSourceFailure)
    case permissionRequired(CapturePermissionState)
    case rejected(CommandRejection)
    case historyDeleted(CaptureID)
    case recognizedText(RecognizedTextOutcome)
    /// Copy Text found no text. Nothing was written to the clipboard (D8, story 89).
    case noTextFound(CaptureRevision)
}

/// The sole action interface. The coordinator owns lifecycle policy and memory.
public struct CaptureCommandLayer: Sendable {
    private let diagnostics: any DiagnosticSink
    private let coordinator: CaptureLifecycleCoordinator

    public init(permission: any CapturePermissionSource, source: any CapturePixelSource, fullScreenSource: (any CapturePixelSource)? = nil,
                windowSource: (any CapturePixelSource)? = nil,
                clipboard: any ImageClipboard, pendingByteLimit: Int,
                diagnostics: any DiagnosticSink = LocalDiagnosticLog(), history: (any CaptureHistory)? = nil, exporter: (any CaptureExport)? = nil,
                drag: (any DragHandoff)? = nil,
                thumbnailPolicy: ThumbnailStackPolicy = ThumbnailStackPolicy(),
                clock: @escaping @Sendable () -> ContinuousClock.Instant = { .now },
                flattener: (any CaptureFlattening)? = nil,
                textRecognizer: (any TextRecognizer)? = nil,
                textClipboard: (any TextClipboard)? = nil) {
        self.diagnostics = diagnostics
        coordinator = CaptureLifecycleCoordinator(permission: permission, source: source, fullScreenSource: fullScreenSource, windowSource: windowSource, clipboard: clipboard,
                                                  pendingByteLimit: pendingByteLimit, history: history, exporter: exporter, drag: drag,
                                                  thumbnailPolicy: thumbnailPolicy, clock: clock, flattener: flattener,
                                                  textRecognizer: textRecognizer, textClipboard: textClipboard)
    }

    /// The thumbnail stack, newest first, with any exit the policy requires now.
    public func thumbnails() async -> [ThumbnailCard] {
        await coordinator.thumbnails()
    }

    /// Keyboard or VoiceOver focus on the stack pauses timeout; overflow still finalizes.
    public func setThumbnailStackFocus(_ focused: Bool) async {
        await coordinator.setThumbnailStackFocus(focused)
    }

    public func setThumbnailPolicy(_ policy: ThumbnailStackPolicy) async {
        await coordinator.setThumbnailPolicy(policy)
    }

    public func assignThumbnailDisplay(_ id: CaptureID, displayID: UInt32) async {
        await coordinator.assignThumbnailDisplay(id, displayID: displayID)
    }

    /// Quit, lock, unlock, and display-unplug outcomes. Quit finalizes oldest first.
    public func handleSystemEvent(_ event: ThumbnailSystemEvent) async -> [CaptureCommandOutcome] {
        await coordinator.handleSystemEvent(event)
    }

    public func focusedThumbnail() async -> CaptureRevision? {
        await coordinator.focusedThumbnail()
    }

    public func moveThumbnailFocus(_ move: ThumbnailFocusMove) async -> CaptureRevision? {
        await coordinator.moveThumbnailFocus(move)
    }

    public func maintainHistory(limits: HistoryLimits? = nil) async -> Result<HistoryUsage, HistoryFailure> {
        await coordinator.maintainHistory(limits: limits)
    }

    public func historyStatus(consumeNotice: Bool = false) async -> Result<HistoryUsage, HistoryFailure> {
        await coordinator.historyStatus(consumeNotice: consumeNotice)
    }

    public func historyEntries() async -> Result<[HistoryEntry], HistoryFailure> {
        await coordinator.historyEntries()
    }

    /// Newest first. Presentation rows carry no file names or paths.
    public func historyItems() async -> Result<[HistoryItem], HistoryFailure> {
        await coordinator.historyItems()
    }

    public func historyThumbnail(_ id: CaptureID) async -> Data? {
        await coordinator.historyThumbnail(id)
    }

    public func historyImage(_ id: CaptureID) async -> CaptureImage? {
        await coordinator.historyImage(id)
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

// Launch action at seam 1; recovery details stay behind CaptureHistory.
extension CaptureCommandLayer {
    public func recoverHistory() async -> Result<HistoryRecoveryReport, HistoryFailure> {
        await coordinator.recoverHistory()
    }

    /// Last open/migration outcome. Does not create History or erase a refused database.
    public func historyAvailability() async -> HistoryFailure? {
        await coordinator.historyAvailability()
    }
}
