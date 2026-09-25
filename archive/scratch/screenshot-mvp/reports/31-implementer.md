# Ticket 31 implementer

Model: Cursor coordinator chat (Claude Opus 5.5 High). Codex and Other Models
are past included-usage limits.

## Seams

- Seam 1: `EditorLeave.deliver` finalizes through Done, then
  `EditorDelivery` copies, saves, or drags that rendered revision. Canaries
  cover the clipboard, saved file, and dragged file. A failed copy leaves the
  commit for retry.

## What landed

- Editor Copy (⌘C) and Save (⌘S) finalize what is on the canvas, then deliver.
- A drag well starts the file-promise session, then uses the same finalize
  + drag command path.
- Delivery failure marks the thumbnail for retry and does not roll back History.

Stopped before review. Ticket Status/checkboxes unchanged.
