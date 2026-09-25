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

    /// DA-3: an editor drag renders without finalizing; only an accepted drop finalizes it.
    @Test func editorCopyAndSaveFinalizeThroughDoneButDragOnlyRendersBeforeDelivering() throws {
        let revision = CaptureRevision(captureID: CaptureID(), number: 1)
        let rendered = CaptureRevision(captureID: revision.captureID, number: 2)
        let edits = try #require(DocumentEdits(scale: 1))
        guard case .done(_, let submitted) = EditorLeave.deliver(edits, .copy).command(for: revision) else {
            Issue.record("Editor copy must Done first"); return
        }
        #expect(submitted == edits)
        guard case .done = EditorLeave.deliver(edits, .save).command(for: revision) else {
            Issue.record("Editor save must Done first"); return
        }
        guard case .render(let left, let rendering) = EditorLeave.deliver(edits, .drag).command(for: revision) else {
            Issue.record("Editor drag must render without finalizing"); return
        }
        #expect(left == revision)
        #expect(rendering == edits)
        guard case .copy(let copied) = EditorDelivery.copy.command(for: rendered) else {
            Issue.record("Editor copy delivers the rendered revision"); return
        }
        #expect(copied == rendered)
        guard case .save(let saved) = EditorDelivery.save.command(for: rendered) else {
            Issue.record("Editor save delivers the rendered revision"); return
        }
        #expect(saved == rendered)
        guard case .drag(let dragged, .copy) = EditorDelivery.drag.command(for: rendered) else {
            Issue.record("Editor drag delivers the rendered revision"); return
        }
        #expect(dragged == rendered)
    }

    @Test func logoutInterruptingAPromptDeletesTheCapture() {
        #expect(EditorLeave.forInterruptedPrompt(.logout) == .delete)
        #expect(EditorLeave.forInterruptedPrompt(.restart) == .delete)
        #expect(EditorLeave.forInterruptedPrompt(.quit) == nil)
    }
}
