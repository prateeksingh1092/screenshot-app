import FrisketCore
import Testing

@Suite struct EditorLeaveTests {
    @Test func unchangedCloseFinalizesThroughDismiss() {
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        guard case .dismiss(let left) = EditorLeave.finalize(nil).command(for: revision) else {
            Issue.record("Unchanged close must dismiss"); return
        }
        #expect(left == revision)
    }

    @Test func editedCloseFinalizesThroughDone() throws {
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        let edits = try #require(DocumentEdits(scale: 1))
        guard case .done(let left, let submitted) = EditorLeave.finalize(edits).command(for: revision) else {
            Issue.record("Edited finalize must Done"); return
        }
        #expect(left == revision)
        #expect(submitted == edits)
    }

    @Test func deleteCaptureDiscardsThePendingID() {
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        guard case .discard(let id) = EditorLeave.delete.command(for: revision) else {
            Issue.record("Delete capture must discard"); return
        }
        #expect(id == revision.captureID)
    }

    @Test func logoutInterruptingAPromptDeletesTheCapture() {
        #expect(EditorLeave.forInterruptedPrompt(.logout) == .delete)
        #expect(EditorLeave.forInterruptedPrompt(.restart) == .delete)
        #expect(EditorLeave.forInterruptedPrompt(.quit) == nil)
    }
}
