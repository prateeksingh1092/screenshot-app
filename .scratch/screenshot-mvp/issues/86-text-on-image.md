# 86: Text typed on the image

**What to build:** A label is typed directly on the image, with a caret and a box, in the pinned CoreText font. The user picks a size from a menu and a style from Standard, Outlined and Box, and sets the width with a side handle (story 104). The toolbar text field goes away.

**Blocked by:** 84

**Phase:** 2b (decision 59)

**Status:** ready-for-agent

- [x] Typing `v2.1 $4.99 -10%` renders exactly those characters.
- [x] Return ends editing without triggering Done, and Esc cancels an empty label.
- [x] Size and style menus are in the Text tool's contextual controls, and the width handle wraps text.
- [x] The saved output equals the preview (the parity test from ticket 68).

## Comments

### 2026-09-25: coordinator, created

From decision 59 (Prateek agreed with the CleanShot editor study). Claude Opus 5.5, Claude Code, high effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62). This ticket's decision in `decisions.md` records the choices.

- **Core:** `Labels.swift` adds `LabelStyle` (Standard, Outlined, Box), `LabelFormat` (style, size 14/18/24/36/48 pt, optional wrap width), `LabelLayout` (line breaks with the pinned `HelveticaNeue-Bold` at the label's size; box and margins), the style painter used by `AnnotationPainter`, and `LabelSession` (typing writes the label into the edits live; one undo step, "Label" or "Edit Label"). `DocumentAnnotation` carries a `label` format (Standard 18 pt by default, so existing goldens are unchanged). A label has a `trailing` width handle ("Resize Label") and `MarkEditor.relabelSelection` ("Restyle Label"). `UndoableEdits.apply(_:named:coalescing:)` folds a typing session into one step on the window's undo manager (decision 77).
- **App:** the toolbar label text field is gone. The Text tool starts typing where you click; a clear `NSTextView` over the rendered label holds the caret (smart substitutions off, its own undo off) and the canvas draws a dashed box. Return/Tab/Esc/click elsewhere end typing, Return is never Done, Esc on a blank label leaves nothing, a Text-tool click on a label edits it. Label Size and Label Style menus sit in the toolbar.
- **Tests:** new `LabelTests` (7 tests, 8 cases): exact characters and glyphs for `v2.1 $4.99 -10%`, one undo step, empty label leaves nothing, width handle wraps (not under one em), size/style restyle, per-style pixel goldens, preview == delivered byte for byte for every style × size × wrap at 1× and 2×. No test was changed; the existing D6, D1 and ticket-68 parity tests still pass.
- **Harness:** `beta-matrix.sh` label rows now click the canvas, type and press Return (`canvas_click`) instead of focusing the removed field; manual check 28 updated.
- **Open (live):** caret alignment over the rendered glyphs, IME/dead-key typing, and the two harness label rows need a live run.

