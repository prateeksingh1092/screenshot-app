# Ticket 17 implementer

Model: Cursor coordinator chat (Claude Opus 5.5 High). Codex and Other Models
are past included-usage limits.

## Seams

Seam 1: `historyAvailability()`, `recoverHistory()`, and `execute` for
capture/copy/save/drag/dismiss against a real `HistoryStore` with corrupt,
unknown-migration, and permission-denied roots.

## What landed

- Typed availability after recover. Open/migration failures do not write.
- Delivery continues; dismiss stays pending when History is refused.
- Repair (remove the bad file) then recover re-enables History without a silent
  erase of the refused database.
- Settings and History window: notice, Try Again, Show History Folder.
- Launch notice when History is already disabled.

Stopped before review. Ticket Status/checkboxes unchanged.
