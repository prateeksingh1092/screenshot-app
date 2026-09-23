/// How the editor is left. Cancel never produces a leave; the window stays open.
public enum EditorLeave: Equatable, Sendable {
    /// Keep the capture. `nil` edits means the document is unchanged, so dismiss finalizes it.
    case finalize(DocumentEdits?)
    /// Delete capture: discard the pending image and write nothing.
    case delete
}

/// A system interruption while the Finalize / Delete / Cancel prompt is unanswered.
public enum EditorInterruption: Equatable, Sendable {
    case quit
    case logout
    case restart
}

extension EditorLeave {
    public func command(for revision: CaptureRevision) -> CaptureCommand {
        switch self {
        case .finalize(nil): return .dismiss(revision)
        case let .finalize(edits?): return .done(revision, edits)
        case .delete: return .discard(revision.captureID)
        }
    }

    /// Logout or restart during an unanswered prompt discards the pending capture.
    public static func forInterruptedPrompt(_ event: EditorInterruption) -> EditorLeave? {
        switch event {
        case .logout, .restart: return .delete
        case .quit: return nil
        }
    }
}
