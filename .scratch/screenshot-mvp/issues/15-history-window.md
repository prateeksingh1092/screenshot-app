# 15: History window

**What to build:** a History window lists finalized captures newest first, and each can be copied, dragged, exported, or deleted.

**Blocked by:** 09, 11, 12

**Status:** resolved (tested on `main` at `19ce435`; History window VoiceOver/exclusion manual pending)

- [x] Items are finished images; there is no re-editing (decision 28).
- [x] Copy, drag, and export reuse the delivery adapters and never hand out app-owned files.
- [x] Delete marks the item `deleting` (hidden, still counted), unlinks files directly (never the Trash), then deletes the row; its interruption points get crash cases.
- [x] Items show no file names or paths; the window is excluded from every capture.
- [x] Full keyboard operation and VoiceOver labels for the list and its actions.

## Comments

### 2026-09-23 — coordinator

Claimed on `331dd49` after ticket 14 closed. Coordinator chat implements (Codex/Other Models still limited).

### 2026-09-23 — implementer

Report: [15-implementer.md](../reports/15-implementer.md). Seam 1 covers delete, newest-first items, copy/save/drag from disk, and interrupted-delete recovery. History window added. Manual not run. Status/checkboxes unchanged pending review.

### 2026-09-23 — review and fix

In-chat review vs `331dd49`: [15-code-review.md](../reviews/15-code-review.md). Fixes: keep delete errors; refresh an open History window when thumbnails finalize; pending re-copy without History stays `.alreadyDelivered`.

- **Integration:** `integrate/15` fast-forwarded `main` to `19ce435`. Newest-first items, delete via `evict`, copy/save/drag from disk, and interrupted-delete recovery are seam 1. Root `swift test`: 250 tests in 36 suites passed. Unsigned x86_64 `xcodebuild` succeeded. x86_64 only; arm64 not executed. Coordinator chat after Codex/Other Models limits. Manual History window VoiceOver/exclusion remain for Prateek.
