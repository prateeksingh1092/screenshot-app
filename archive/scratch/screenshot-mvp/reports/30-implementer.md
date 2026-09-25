# Ticket 30 implementer

Model: Cursor coordinator chat (Claude Opus 5.5 High). Codex and Other Models
are past included-usage limits.

## Seams

- Seam 1: `EditorLeave` maps unchanged close to dismiss, edited finalize to
  Done, Delete capture to discard, and logout/restart during an unanswered
  prompt to discard. Adapter tests execute those commands.

## What landed

- Close without edits finalizes to History.
- Close with edits shows Finalize (Return, default), Delete Capture
  (destructive, never default), and Cancel (Esc).
- Quit offers the same sheet on each open editor. Sudden termination is
  disabled while any editor is open.
- `willPowerOff` discards a capture whose prompt is still unanswered.

Stopped before review. Ticket Status/checkboxes unchanged.
