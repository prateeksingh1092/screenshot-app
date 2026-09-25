import FrisketCore
import Testing

/// Ticket 76 (DA-5, story 99): notices never block. Every outcome maps to a non-modal `Notice`
/// or to none; only the destructive `Confirmation`s may interrupt, and Quit never refuses.
@Suite struct NoticeTests {
    private static let id = CaptureID()
    private static let revision = CaptureRevision(captureID: id, number: 1)
    private static let receipt = ClipboardReceipt(changeCount: 1)
    private static let reasons: [CommitUnavailableReason] = [
        .historyUnavailable, .unknownMigrations, .invalidImage, .recoveryRequired, .captureExceedsHistoryLimit,
    ]
    private static let commits: [CommitOutcome] = [.committed] + reasons.map { .notCommitted($0) }

    private static func commands() throws -> [CaptureCommand] {
        let edits = try #require(DocumentEdits(scale: 1))
        return [
            .capture(id, maximumBytes: 1), .captureFullScreen(id, maximumBytes: 1), .captureWindow(id, maximumBytes: 1),
            .copy(revision), .retryCopy(revision), .save(revision), .retrySave(revision),
            .dismiss(revision), .discard(id), .exitThumbnail(revision, .close), .exitThumbnail(revision, .delete),
            .drag(revision, .copy), .done(revision, edits), .render(revision, edits),
            .deleteHistory(id), .copyRecognizedText(revision),
        ]
    }

    private static var outcomes: [CaptureCommandOutcome] {
        var all: [CaptureCommandOutcome] = [.pending(revision), .discarded(id), .historyDeleted(id), .noTextFound(revision)]
        for commit in commits {
            all.append(.copy(CopyOutcome(revision: revision, commit: commit, delivery: .copied(receipt))))
            all.append(.copy(CopyOutcome(revision: revision, commit: commit, delivery: .failed(.unavailable))))
            all.append(.save(SaveOutcome(revision: revision, commit: commit, delivery: .saved(ExportReceipt(filename: "a.png")))))
            all.append(.save(SaveOutcome(revision: revision, commit: commit, delivery: .failed(.unwritable))))
            all.append(.finalized(revision, commit))
            all.append(.drag(DragOutcome(revision: revision, commit: commit, delivery: .copied)))
            all.append(.edited(revision, commit))
            all.append(.edited(revision, commit, clipboardFailure: .changed))
        }
        all.append(.drag(DragOutcome(revision: revision, commit: nil, delivery: .failed)))
        all.append(.rendered(revision))
        all.append(.rendered(revision, clipboardFailure: .changed))
        all += [CaptureSourceFailure.unavailable, .emptyImage, .cancelled, .permissionRequired(.denied)]
            .map { .captureFailed($0) }
        all += WindowCaptureFailure.allCases.map { .captureFailed(.window($0)) }
        all.append(.permissionRequired(.denied))
        all += [CommandRejection.commandInProgress, .staleRevision, .pendingByteBudgetExceeded, .editingUnavailable]
            .map { .rejected($0) }
        all.append(.recognizedText(RecognizedTextOutcome(revision: revision, characterCount: 3, delivery: .copied(receipt))))
        return all
    }

    /// Every command outcome maps to a non-modal notice or to none, and every notice has words to announce.
    @Test func everyOutcomeMapsToANonModalNoticeOrNone() throws {
        var shown = 0
        for command in try Self.commands() {
            for outcome in Self.outcomes {
                guard let notice = Notice.after(command, outcome) else { continue }
                shown += 1
                #expect(!notice.title.isEmpty && !notice.message.isEmpty)
                #expect(notice.announcement.contains(notice.title) && notice.announcement.contains(notice.message))
            }
        }
        #expect(shown > 0)
    }

    /// A success is not announced as a notice: the Thumbnail's own status and removal say it.
    /// Save is the exception: its file lands out of sight, so it confirms (below).
    @Test func successOutcomesShowNoNotice() throws {
        let edits = try #require(DocumentEdits(scale: 1))
        let successes: [(CaptureCommand, CaptureCommandOutcome)] = [
            (.capture(Self.id, maximumBytes: 1), .pending(Self.revision)),
            (.captureWindow(Self.id, maximumBytes: 1), .captureFailed(.cancelled)),
            (.copy(Self.revision), .copy(CopyOutcome(revision: Self.revision, commit: .committed, delivery: .copied(Self.receipt)))),
            (.drag(Self.revision, .copy), .drag(DragOutcome(revision: Self.revision, commit: .committed, delivery: .copied))),
            (.dismiss(Self.revision), .finalized(Self.revision, .committed)),
            (.exitThumbnail(Self.revision, .close), .finalized(Self.revision, .committed)),
            (.done(Self.revision, edits), .edited(Self.revision, .committed)),
            (.render(Self.revision, edits), .rendered(Self.revision)),
            (.discard(Self.id), .discarded(Self.id)),
        ]
        for (command, outcome) in successes {
            #expect(Notice.after(command, outcome) == nil, "\(outcome)")
        }
    }

    /// D17: Save confirms on the notice line, not with a modal, and names the file (ticket 81).
    @Test func saveConfirmsWithTheExportName() {
        let saved = SaveOutcome(revision: Self.revision, commit: .committed,
                                delivery: .saved(ExportReceipt(filename: "Frisket 2026-09-25 at 14.03.07.png")))
        for command in [CaptureCommand.save(Self.revision), .retrySave(Self.revision)] {
            let notice = Notice.after(command, .save(saved))
            #expect(notice == .saved("Frisket 2026-09-25 at 14.03.07.png"))
            #expect(notice?.announcement.contains("Frisket 2026-09-25 at 14.03.07.png") == true)
        }
        // A save History could not keep still says so instead.
        let unkept = SaveOutcome(revision: Self.revision, commit: .notCommitted(.historyUnavailable), delivery: saved.delivery)
        #expect(Notice.after(.save(Self.revision), .save(unkept)) == .savedButNotInHistory)
    }

    @Test func failuresTheUserMustKnowAboutShowANotice() throws {
        let edits = try #require(DocumentEdits(scale: 1))
        #expect(Notice.after(.capture(Self.id, maximumBytes: 1), .captureFailed(.unavailable)) == .captureUnavailable)
        #expect(Notice.after(.capture(Self.id, maximumBytes: 1), .rejected(.pendingByteBudgetExceeded)) == .tooManyPendingCaptures)
        #expect(Notice.after(.captureWindow(Self.id, maximumBytes: 1), .captureFailed(.window(.noWindow)))
                == Notice(title: WindowCaptureFailure.noWindow.title, message: WindowCaptureFailure.noWindow.message))
        #expect(Notice.after(.save(Self.revision), .save(SaveOutcome(revision: Self.revision, commit: .notCommitted(.historyUnavailable),
                                                                     delivery: .saved(ExportReceipt(filename: "a.png"))))) == .savedButNotInHistory)
        #expect(Notice.after(.copy(Self.revision), .copy(CopyOutcome(revision: Self.revision, commit: .notCommitted(.captureExceedsHistoryLimit),
                                                                     delivery: .copied(Self.receipt)))) == .exceedsHistoryLimit)
        #expect(Notice.after(.done(Self.revision, edits), .rejected(.commandInProgress)) == .editNotFinished)
        #expect(Notice.after(.done(Self.revision, edits), .edited(Self.revision, .committed, clipboardFailure: .changed)) == .earlierCopyNotReplaced)
    }

    /// The only modal choices: delete, close with edits (which Quit reaches through each unanswered editor),
    /// and an export folder that sends copies off this Mac.
    @Test func onlyDestructiveOrIrreversibleChoicesAreModal() {
        #expect(Set(Confirmation.allCases) == [.deleteFromHistory, .closeEditedCapture, .useSyncingExportFolder])
    }

    /// Live evidence: a harness stopped mid-selection, and Quit refused with a modal "Finish the current action"
    /// although no overlay was visible. Quit now never refuses: it cancels a selection, waits for commands,
    /// finalizes Thumbnails and quits. Only an editor with unanswered edits holds it, through its own prompt.
    @Test func quitNeverRefusesExceptThroughAnUnansweredEditor() {
        for bits in 0..<16 {
            let state = QuitState(editorOpen: bits & 1 != 0, captureInFlight: bits & 2 != 0,
                                  thumbnailCommandInFlight: bits & 4 != 0, thumbnailsShown: bits & 8 != 0)
            let steps = QuitPlan.steps(for: state)
            if state.editorOpen {
                #expect(steps == [.offerEditorsToLeave])
            } else {
                #expect(steps.last == .quit, "\(state)")
                #expect(steps.contains(.cancelCapture) == state.captureInFlight)
                #expect(steps.contains(.waitForThumbnailCommands) == state.thumbnailCommandInFlight)
                #expect(steps.contains(.finalizeThumbnails) == (state.thumbnailsShown || state.captureInFlight))
            }
        }
    }

    @Test func aStaleCaptureFlagDoesNotHoldQuit() {
        let steps = QuitPlan.steps(for: QuitState(editorOpen: false, captureInFlight: true,
                                                   thumbnailCommandInFlight: false, thumbnailsShown: false))
        #expect(steps == [.cancelCapture, .finalizeThumbnails, .quit])
    }
}
