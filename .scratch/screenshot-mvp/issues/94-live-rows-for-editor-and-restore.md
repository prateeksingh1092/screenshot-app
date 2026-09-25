# 94: Live rows for Restore and the new editor features

**What to build:** Live-matrix rows for the checks that tickets 69, 79, 84, 85, 86 and 92 left to a person, so Prateek's acceptance test (83) covers only look and feel.

**Blocked by:** none

**Status:** ready-for-agent (medium effort)

Rows, each verified through the clipboard, pixels or AX, never by eye:
- [ ] `history-restore` (79): History › Restore to Thumbnail brings back a finalized Thumbnail with Copy and no Edit. Copy gives that capture, and closing the Thumbnail adds no History row.
- [ ] `editor-undo-names` (69): after a Crop and an Arrow, Edit › Undo reads "Undo Arrow". ⌘Z then ⌘⇧Z restores the arrow, checked through Copy.
- [ ] `editor-mark-keyboard` (84): select a Shape, Tab to it, move it with the arrow keys, then Delete. Copy shows it moved, then gone.
- [ ] `editor-curved-arrow` (85): drawing a Curved arrow and dragging its middle handle leaves ink off the straight line between its ends.
- [ ] `editor-label-typed` (86): a Box-style label typed on the image, then Return. Done is not triggered, and Copy Text reads the typed string.
- [ ] `editor-style-bar` (92): the style bar shows the colour buttons for Solid Redaction, the Arrow style menu for Arrow, and the size and style menus for Text. No toolbar item sits in the » overflow.

## Comments

### 2026-09-25: coordinator, created

Prateek approved automating the rest of 83's by-hand checks. Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62).

- `Tools/LiveHarness/matrix.tsv`: six rows, `history-restore`, `editor-undo-names`, `editor-mark-keyboard`, `editor-curved-arrow`, `editor-label-typed` and `editor-style-bar`, each `pass` with no defect.
- `Tools/LiveHarness/beta-matrix.sh`: their `row_<id>` functions, built on the existing helpers, plus `undo_title` (the Undo button's tooltip, which uses the same `undoMenuItemTitle` as Edit › Undo), `pick` (sets a style-bar pop-up by AX and checks its value) and `inside_editor` (a control's frame lies inside the editor window).
- `Tools/LiveHarness/drive.swift`: `drive menu PID TITLE` lists a main-menu menu's items, opening it first so AppKit validates titles such as "Undo Arrow".
- `Tools/LiveHarness/README.md`: a note listing the new rows.

Not run live (the coordinator runs `--live`); `--dry-run`, `bash -n` and `scripts/ci.sh` only. The criteria stay unticked until the first live run passes. Assumptions for that run are in the coordinator's report: the Edit menu of an accessory app may not open or validate by AX; AX presses on pop-ups; hidden style-bar controls; thin curved-arrow ink at 1×; 1× OCR of an 18 pt Box label. Twenty-eight rows may not fit one 9-minute run per display; use `--row` for the new ones if needed.
