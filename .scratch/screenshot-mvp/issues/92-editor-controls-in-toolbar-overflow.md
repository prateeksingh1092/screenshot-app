# 92: Editor controls hide in the toolbar overflow (D29)

**What to build:** At the editor's default width every editor control is reachable without the toolbar's "more toolbar items" (») menu: the tools, the Solid redaction colour buttons (ticket 88), the arrow style and line width menus (tickets 84, 85), and the label size and style menus (ticket 86). Done, Copy and Save stay on screen (D5).

**Evidence (2026-09-25, live, `fe7fa6e`, external display, 320×180 pt capture, editor window 760 pt wide):** the AX toolbar lists Select … Magnify, then `more toolbar items`. There is no `Redaction colour` element, so the `editor-redaction` row can't choose Grey (run `20260925-122437`). The canvas description still reads "Drag to hide pixels with a solid black redaction", from before decision 61.

**Blocked by:** none

**Status:** ready-for-agent (medium effort)

- [x] The colour, style, width, size and label-style controls are reachable at the default editor width, with no overflow menu. One way to do that is contextual controls for the active tool or selected mark, as in the CleanShot study (decision 59).
- [x] The canvas accessibility description names the chosen redaction colour, not "black".
- [ ] Live: the `editor-redaction` row (Grey) and `editor-finish-visible` pass on both displays.

## Comments

### 2026-09-25: coordinator, created

Found in the first live run after tickets 84–88. Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62).

- **Choice (this ticket's decision in `decisions.md`):** a style bar, a 32-point row at the top of the editor's content area, above the hint line, holds the Solid redaction colour swatches, the Arrow style and Line width menus and the Label size and Label style menus. It shows only the controls for the selected mark, or else for the active tool (CleanShot's contextual controls, decision 59). The toolbar keeps only the tools, Undo and Close, so nothing overflows at 760 pt. Done, Copy and Save stay in the action bar (D5).
- **Core seam:** `StyleBar.controls(tool:selection:in:)` and `EditorToolKind` in FrisketCore (`StyleBar.swift`); each app tool names its kind; `EditorWindow.refresh` hides and shows the controls from that list. `CONTEXT.md` gains **Style bar**.
- **Accessibility:** labels unchanged ("Redaction colour: <Name>", "Arrow style", "Line width", "Label size", "Label style", tool buttons, "Copy edited capture"); the bar is a group named "Style". The canvas description now reads "Drag to hide pixels with a Solid redaction in <Colour>." (decision 61).
- **Tests:** `StyleBarTests` (3 tests): each tool's controls, a selected mark's controls with every tool, and a styleless or stale selection falling back to the tool. Red (missing symbols) then green. No `knownDefect("D29")` test existed; the layout is a live check.
- **Open (live):** the `editor-redaction` row (Grey) and `editor-finish-visible` on both displays; confirm the toolbar shows no » at 760 pt and at the 560 pt minimum.
