# 15: History window

**What to build:** a History window lists finalized captures newest first, and each can be copied, dragged, exported, or deleted.

**Blocked by:** 09, 11, 12

**Status:** in-progress (branch `ticket/15-history-window`)

- [ ] Items are finished images; there is no re-editing (decision 28).
- [ ] Copy, drag, and export reuse the delivery adapters and never hand out app-owned files.
- [ ] Delete marks the item `deleting` (hidden, still counted), unlinks files directly (never the Trash), then deletes the row; its interruption points get crash cases.
- [ ] Items show no file names or paths; the window is excluded from every capture.
- [ ] Full keyboard operation and VoiceOver labels for the list and its actions.

## Comments

### 2026-09-23 — coordinator

Claimed on `331dd49` after ticket 14 closed. Coordinator chat implements (Codex/Other Models still limited).
