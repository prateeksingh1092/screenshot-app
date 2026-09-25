# 69: Editor undo through NSUndoManager

**What to build:** Undo and Redo in the editor use the window's `NSUndoManager`, so ⌘Z, ⌘⇧Z and the Edit menu work the same way for every edit kind, crop included.

**Blocked by:** 53, 68

**Phase:** 2 (O11)

**Status:** ready-for-agent

- [x] The custom undo stack is deleted.
- [x] Every edit kind undoes and redoes, and the Undo menu item names the edit.
- [x] The close-with-edits choice is unchanged.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62).

- **Changed:** new FrisketCore `UndoableEdits` (`Sources/FrisketCore/UndoableEdits.swift`) holds the editor's `DocumentEdits` and registers every change on a Foundation `UndoManager`, named Solid Redaction, Crop, Shape, Arrow, Label, Blur or Magnify. `EditorWindow` returns that manager from `windowWillReturnUndoManager(_:)`, applies drags through it and refreshes on every change; `undoStack` is deleted. `EditorKeyWindow` handles `undo:` and the new `redo:` (so Edit › Redo, ⌘⇧Z, works), sets the menu titles from the manager ("Undo Crop"), and refuses both while the editor finishes. The toolbar Undo tooltip names the edit. Closing still asks only when the edits are not empty (`isUnchanged` replaces the old check), so undoing everything closes without asking, as before.
- **Grouping:** the manager groups by event (AppKit's default, which label-field typing needs), so one canvas drag is one undo step.
- **Tests:** `Tests/FrisketCoreTests/UndoableEditsTests.swift` (5 tests): every edit kind undoes and redoes with its action name; seven edits undo in reverse and redo forward; a new edit clears Redo; a no-op edit registers nothing; undo and redo notify the editor. Red first (type missing), then green. The tests pump the main run loop once per edit to close the event's group, as a mouse-up does in the app. No existing test changed.
- **Decision:** this ticket's decision in `decisions.md`.
- **Open, live matrix:** ⌘Z/⌘⇧Z and Edit › Undo/Redo titles in the running editor, crop included; Undo while typing in the label field (shares the manager, so it undoes typing first); the close sheet after edits and after undoing all of them.
