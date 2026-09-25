/// Something Frisket tells the user. A notice never blocks (DA-5, ticket 76): the app shows it on the
/// capture's Thumbnail status line, or on the notice line when no Thumbnail is showing, and VoiceOver
/// announces it. Only a `Confirmation` may interrupt with a modal.
public struct Notice: Equatable, Sendable {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    /// What VoiceOver reads.
    public var announcement: String { "\(title). \(message)" }
}

/// The only choices that may interrupt with a modal: destructive or irreversible ones (DA-5).
public enum Confirmation: CaseIterable, Sendable {
    /// History Delete removes the capture at once, with no undo (DA-4).
    case deleteFromHistory
    /// Closing an editor with edits: Finalize, Delete capture or Cancel. Quit reaches it through each open editor.
    case closeEditedCapture
    /// An export folder that syncs copies to iCloud and other devices; they can't be called back.
    case useSyncingExportFolder
}

extension Notice {
    /// The notice, if any, that follows a command's outcome. A success returns nil: the Thumbnail's
    /// status and its leaving say it. A failure the Thumbnail already shows as a Retry control also returns nil.
    public static func after(_ command: CaptureCommand, _ outcome: CaptureCommandOutcome) -> Notice? {
        switch outcome {
        case .pending, .discarded, .historyDeleted, .restored, .finalized(_, .committed), .permissionRequired,
             .recognizedText, .noTextFound:
            return nil
        case .captureFailed(.cancelled), .captureFailed(.permissionRequired):
            return nil
        case let .captureFailed(.window(failure)):
            return Notice(title: failure.title, message: failure.message)
        case .captureFailed:
            return .captureUnavailable
        case let .copy(copy):
            guard case .copied = copy.delivery else { return limitNotice(copy.commit) }
            return copy.commit == .notCommitted(.recoveryRequired) ? .historyNeedsRecovery : limitNotice(copy.commit)
        case let .save(save):
            guard case .saved = save.delivery else { return limitNotice(save.commit) }
            if case .notCommitted(let reason) = save.commit, reason != .captureExceedsHistoryLimit { return .savedButNotInHistory }
            return limitNotice(save.commit)
        case let .drag(drag):
            guard drag.delivery == .copied, let commit = drag.commit else { return nil }
            if case .notCommitted(let reason) = commit, reason != .captureExceedsHistoryLimit { return .draggedButNotInHistory }
            return limitNotice(commit)
        case let .finalized(_, commit):
            return limitNotice(commit)
        case let .edited(_, commit, clipboardFailure):
            return clipboardFailure != nil ? .earlierCopyNotReplaced : limitNotice(commit)
        case let .rendered(_, clipboardFailure):
            return clipboardFailure != nil ? .earlierCopyNotReplaced : nil
        case .rejected:
            switch command {
            case .capture, .captureFullScreen, .captureWindow: return .tooManyPendingCaptures
            case .done, .render: return .editNotFinished
            case .dismiss: return .captureNotKept
            default: return nil   // the Thumbnail shows Retry on its status line
            }
        }
    }

    private static func limitNotice(_ commit: CommitOutcome) -> Notice? {
        commit == .notCommitted(.captureExceedsHistoryLimit) ? .exceedsHistoryLimit : nil
    }

    public static let captureUnavailable = Notice(title: "Capture unavailable",
        message: "A disconnected display or an oversized capture can prevent capture. Try again with a smaller area.")
    public static let tooManyPendingCaptures = Notice(title: "Capture unavailable",
        message: "Copy or delete pending captures, then try again.")
    public static let previewUnavailable = Notice(title: "Preview unavailable",
        message: "The capture could not be displayed and was deleted.")
    public static let editedPreviewUnavailable = Notice(title: "Preview unavailable",
        message: "The redacted capture couldn't be shown or kept in History.")
    public static let editorUnavailable = Notice(title: "Editor unavailable",
        message: "This capture can't be edited. Copy, dismiss, or delete it instead.")
    public static let captureNotKept = Notice(title: "Could not keep the capture",
        message: "History did not accept this capture. Copy or Save it, then try again.")
    public static let editNotFinished = Notice(title: "Could not finish editing",
        message: "Your edits are still open. Done could not prepare the redacted result. Press Done again to finish editing.")
    public static let earlierCopyNotReplaced = Notice(title: "Could not replace the earlier copy",
        message: "The clipboard may still contain the original capture. Use Copy on the redacted thumbnail to replace it.")
    public static let historyNeedsRecovery = Notice(title: "History needs recovery",
        message: "The capture was copied, but History could not finish keeping it. This capture cannot be edited.")
    public static let savedButNotInHistory = Notice(title: "Could not add to History",
        message: "The PNG was saved to the export folder, but could not be added to History.")
    public static let draggedButNotInHistory = Notice(title: "Could not add to History",
        message: "The capture was dragged out, but could not be added to History.")
    public static let exceedsHistoryLimit = Notice(title: "Capture exceeds History size limit",
        message: "This capture could not be kept in History. Copy and Save remain available. Increase the size limit in Settings to keep larger captures.")
    public static let historyQuotaReached = Notice(title: "History size limit reached",
        message: "Older captures were removed from History to meet its size limit. Saved exports are unchanged. You can adjust the limit in Settings.")
    public static func historyOff(_ text: String) -> Notice { Notice(title: "History is off", message: text) }
    public static let systemShortcutsNotRestored = Notice(title: "Could not restore macOS shortcuts",
        message: "Turn them on in System Settings › Keyboard › Keyboard Shortcuts › Screenshots.")
    public static let openScreenRecordingSettings = Notice(title: "Open System Settings",
        message: "Open Privacy & Security → Screen & System Audio Recording and enable Frisket.")
    public static let cannotReopen = Notice(title: "Could not reopen Frisket",
        message: "Launch Frisket from ~/Applications/Frisket.app, then try Quit & Reopen again.")
    public static let cannotReopenWhileQuitting = Notice(title: "Could not reopen Frisket",
        message: "Frisket is quitting. Launch it from ~/Applications/Frisket.app to reopen it.")
    public static let quitNotFinished = Notice(title: "Frisket did not quit",
        message: "A capture could not be added to History. Copy, Save or delete it, then quit again.")
}

/// What Quit has to deal with. Termination is decided here, in one place (story 99).
public struct QuitState: Equatable, Sendable {
    public var editorOpen: Bool
    /// A capture command is running: a selection may be open, or the flag may be stale (live evidence, ticket 76).
    public var captureInFlight: Bool
    public var thumbnailCommandInFlight: Bool
    public var thumbnailsShown: Bool

    public init(editorOpen: Bool, captureInFlight: Bool, thumbnailCommandInFlight: Bool, thumbnailsShown: Bool) {
        self.editorOpen = editorOpen
        self.captureInFlight = captureInFlight
        self.thumbnailCommandInFlight = thumbnailCommandInFlight
        self.thumbnailsShown = thumbnailsShown
    }
}

public enum QuitStep: Equatable, Sendable {
    /// Each open editor asks Finalize, Delete capture or Cancel (`Confirmation.closeEditedCapture`); Quit waits for the answer.
    case offerEditorsToLeave
    /// Close any selection overlay. A capture still in memory is dropped; nothing of it is on disk.
    case cancelCapture
    /// Let a Copy, Save or drag already running finish (bounded).
    case waitForThumbnailCommands
    /// Add every pending capture to History, oldest first.
    case finalizeThumbnails
    case quit
}

/// Quit never refuses with a notice. Only an editor holds it, through its own destructive choice.
public enum QuitPlan {
    public static func steps(for state: QuitState) -> [QuitStep] {
        if state.editorOpen { return [.offerEditorsToLeave] }
        var steps: [QuitStep] = []
        if state.captureInFlight { steps.append(.cancelCapture) }
        if state.thumbnailCommandInFlight { steps.append(.waitForThumbnailCommands) }
        // A capture that finishes while its selection closes becomes a pending Thumbnail, so finalize after cancelling.
        if state.thumbnailsShown || state.captureInFlight { steps.append(.finalizeThumbnails) }
        steps.append(.quit)
        return steps
    }
}
