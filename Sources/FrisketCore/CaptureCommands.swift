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
    /// Puts a History item back in the stack as a finalized Thumbnail: Copy, Save, drag and Copy Text,
    /// no Edit, and leaving it never commits again (ticket 79, DA-10, decision 28).
    case restoreFromHistory(CaptureID)
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
    /// The History item is listed as a finalized Thumbnail at History's revision (ticket 79).
    case restored(CaptureRevision)
    case recognizedText(RecognizedTextOutcome)
    /// Copy Text found no text. Nothing was written to the clipboard (D8, story 89).
    case noTextFound(CaptureRevision)
}
