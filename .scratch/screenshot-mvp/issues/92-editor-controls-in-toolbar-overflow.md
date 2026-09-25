# 92: Editor controls hide in the toolbar overflow (D29)

**What to build:** At the editor's default width every editor control is reachable without the toolbar's "more toolbar items" (») menu: the tools, the Solid redaction colour buttons (ticket 88), the arrow style and line width menus (tickets 84, 85), and the label size and style menus (ticket 86). Done, Copy and Save stay on screen (D5).

**Evidence (2026-09-25, live, `fe7fa6e`, external display, 320×180 pt capture, editor window 760 pt wide):** the AX toolbar lists Select … Magnify, then `more toolbar items`. There is no `Redaction colour` element, so the `editor-redaction` row can't choose Grey (run `20260925-122437`). The canvas description still reads "Drag to hide pixels with a solid black redaction", from before decision 61.

**Blocked by:** none

**Status:** ready-for-agent (medium effort)

- [ ] The colour, style, width, size and label-style controls are reachable at the default editor width, with no overflow menu. One way to do that is contextual controls for the active tool or selected mark, as in the CleanShot study (decision 59).
- [ ] The canvas accessibility description names the chosen redaction colour, not "black".
- [ ] Live: the `editor-redaction` row (Grey) and `editor-finish-visible` pass on both displays.

## Comments

### 2026-09-25: coordinator, created

Found in the first live run after tickets 84–88. Claude Opus 5.5, Claude Code, medium effort.
