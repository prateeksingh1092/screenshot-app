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
