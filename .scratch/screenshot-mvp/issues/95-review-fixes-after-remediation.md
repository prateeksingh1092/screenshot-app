# 95: Fixes from the review of the 2026-09-25 merges

**What to build:** Four defects found by the code review of `a724abd..fa2be6c`.

**Blocked by:** none

**Status:** ready-for-agent (medium effort)

- [ ] **Overflow spares the capture being edited (coordinator's decision).** While the editor is open for a capture, stack overflow exits the oldest *other* card. When the editor leaves, the timeout restarts in full, as decision 76 says. Today `ThumbnailStack.swift:208` marks it due and only `panel.model.busy` holds it (`CaptureSurfaces.swift:435`), so Done after four more captures closes it within about 1.2 s. Add a red test through `thumbnails()`/`execute` first.
- [ ] **Restore during the exit animation.** Pressing Restore (`HistoryWindow.swift:202`) while that capture's card is animating out shows "Could not restore… Try again." It should restore once the exit finishes, or keep the card, never show a false failure.
- [ ] **Undo names.** `UndoableEdits.actionName` (`UndoableEdits.swift:69-76`) names any annotation change after the last annotation. Name the mark that actually changed, and share one noun function with `MarkEditing.swift:274-276`.
- [ ] **Labels hold only typed characters.** The label text view (`EditorWindow.swift` ~908-914) also turns off `inlinePredictionType` and `writingToolsBehavior`, so no text arrives that the user didn't type, and label text never leaves the device.

## Comments

### 2026-09-25: coordinator, created

From the review of today's merges. Claude Opus 5.5, Claude Code, medium effort.
