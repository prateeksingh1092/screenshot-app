# 84: Editable marks

**What to build:** After drawing, a mark stays an object. The user selects it with a click (or a select tool) and sees handles. They can move, resize or delete it, and change its colour or width; each change is one undo step (story 102). Solid redactions keep their own rules and stay exact black.

**Blocked by:** 66, 69

**Phase:** 2b (decision 59)

**Status:** ready-for-agent

- [x] Clicking a mark selects it and shows handles. Esc or a click elsewhere deselects it.
- [x] Move, resize, delete and restyle each produce one `NSUndoManager` step.
- [x] The saved output equals the preview after every edit (the parity test from ticket 68).
- [x] Every mark has a VoiceOver label, and a keyboard path exists: Tab through marks, arrows to move, Delete to delete.

## Comments

### 2026-09-25: coordinator, created

From decision 59 (Prateek agreed with the CleanShot editor study). Claude Opus 5.5, Claude Code, high effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62).

**What changed and why.** The logic lives in the core so it is tested there; the window stays thin (this ticket's decision in `decisions.md`).
- `Sources/FrisketCore/MarkEditing.swift` (new): `MarkReference`, `MarkHandle`, `MarkChange`, hit-testing, handles, `DocumentEdits.applying(_:to:)`, VoiceOver labels, `MarkKey` (Tab, Shift-Tab, arrows, Delete) and `MarkEditor`, which holds the selection and makes each change one named undo step through the new `UndoableEdits.apply(_:named:)`.
- `DocumentAnnotation` carries its ink colour (opaque only) and line width (default 2 pt, the old pen); `AnnotationPainter` draws each mark's own ink and width, so the preview and the delivered image both follow a restyle. Defaults are unchanged, so every existing golden holds.
- `Frisket/EditorTool.swift`: a Select tool (V). `Frisket/EditorWindow.swift`: press and release go through `MarkEditor`; the canvas draws the blue outline and handles, takes focus for Tab, arrows and Delete, exposes each mark as a labelled accessibility child and announces selection changes; Esc deselects first; a line-width menu (2, 4, 8 pt) restyles a selected shape or arrow. No pbxproj change.
- "Stay exact black" is read as decision 61: a moved or resized Solid redaction keeps its chosen colour at alpha 255; a translucent recolour is refused. No colour control is added: the palette is ticket 88, which can call `MarkEditor.recolourSelection`.
- `CONTEXT.md` gains **Mark**.

**Tests** (`Tests/FrisketCoreTests/EditableMarksTests.swift`, 12 tests, written against the new API first, so red until it existed): click selection, topmost hit, Esc; move, resize (box and arrow), nudge, delete and both restyles as one named undo step each; refused changes register nothing; redaction colour kept; Tab order; VoiceOver labels relative to the crop; presses on a cropped canvas; preview equals `flatten` byte for byte after nine successive mark edits; a wider recoloured arrow is drawn in its own ink and width; key mapping. No existing test changed.

**Open, for the live matrix:** handles and selection by mouse, keyboard Tab/arrows/Delete, the VoiceOver reading of marks, and the width menu, in the running editor. Colour restyle has no control until ticket 88. A label has no resize handle until ticket 86.

