# 95: Fixes from the review of the 2026-09-25 merges

**What to build:** Four defects found by the code review of `a724abd..fa2be6c`.

**Blocked by:** none

**Status:** implemented, awaiting coordinator review (medium effort)

- [x] **Overflow spares the capture being edited (coordinator's decision).** While the editor is open for a capture, stack overflow exits the oldest *other* card. When the editor leaves, the timeout restarts in full, as decision 76 says. Today `ThumbnailStack.swift:208` marks it due and only `panel.model.busy` holds it (`CaptureSurfaces.swift:435`), so Done after four more captures closes it within about 1.2 s. Add a red test through `thumbnails()`/`execute` first.
- [x] **Restore during the exit animation.** Pressing Restore (`HistoryWindow.swift:202`) while that capture's card is animating out shows "Could not restore… Try again." It should restore once the exit finishes, or keep the card, never show a false failure.
- [x] **Undo names.** `UndoableEdits.actionName` (`UndoableEdits.swift:69-76`) names any annotation change after the last annotation. Name the mark that actually changed, and share one noun function with `MarkEditing.swift:274-276`.
- [x] **Labels hold only typed characters.** The label text view (`EditorWindow.swift` ~908-914) also turns off `inlinePredictionType` and `writingToolsBehavior`, so no text arrives that the user didn't type, and label text never leaves the device.

## Comments

### 2026-09-25: coordinator, created

From the review of today's merges. Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62).

- **Overflow (this ticket's decision, amends decision 76):** `ThumbnailStack.cards(at:sparing:)` and `admits(_:for:at:sparing:)` pick overflow oldest first, skipping captures whose editor is open; `CaptureLifecycleCoordinator` passes its `editorOpen` set. Test `overflowSparesTheCaptureBeingEditedAndExitsTheOldestOtherCard` (through `execute`/`thumbnails()`): red before (the edited card was due for overflow), green after. Leaving the editor restarts the full timeout, as before.
- **Restore during the exit animation:** `CaptureSurfaces` keeps the 1.2 s "Capture kept in History" exit as a task in `exiting`; `restoreFromHistory` awaits it, then restores into a new card, so no false "Could not restore". No package test: the race is between the app's panel animation and History's button (both in the app target); the core half (restore after a card exits) is already covered by ticket 79's tests. Check live: Restore a capture while its card animates out.
- **Undo names:** `UndoableEdits.actionName` now names the first mark that differs (from the old edits when a mark was removed) through `DocumentEdits.noun(for:)`, the same function mark editing uses. Test `anEditNamesTheMarkItChangedNotTheNewestMark`: red before ("Label"/"Magnify" for arrow/blur changes), green after.
- **Labels:** the label text view sets `inlinePredictionType = .no` and `writingToolsBehavior = .none`, keeping the substitution settings. AppKit only; no test.
- Open: none beyond the live Restore check.
