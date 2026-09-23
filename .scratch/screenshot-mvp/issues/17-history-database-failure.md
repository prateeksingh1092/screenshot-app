# 17: History database failure mode

**What to build:** if the History database can't be opened or migrated, History turns off with a visible notice and a recovery option, while capturing, copying, saving, and dragging keep working (decision 40).

**Blocked by:** 09, 11, 12

**Status:** resolved (tested on `main` at `43b93ae`; History failure notice/folder manual pending)

- [x] Open and migration failures (corrupt file, unknown migration, permission denied) put History in a disabled state without writing to the database.
- [x] A visible notice and a recovery option are shown; the recovery never erases the database silently.
- [x] Seam 1 tests prove capture, copy, save, and drag still succeed in the disabled state, and that dismiss behaves safely without History.

## Comments

### 2026-09-23 — coordinator

Claimed on `9abd3c2` after ticket 15 closed. Coordinator chat implements (Codex/Other Models still limited). Seam 1: corrupt, unknown-migration, and permission failures disable History without writing; capture/copy/save/drag continue; recover retries without deleting the database.

### 2026-09-23 — implementer

Report: [17-implementer.md](../reports/17-implementer.md). Seam 1 covers corrupt, unknown-migration, and permission-denied open failures plus recover-after-repair. Settings/History window notice and recovery actions added. Manual not run. Status/checkboxes unchanged pending review.

### 2026-09-23 — review and fix

In-chat review vs `9abd3c2`: [17-code-review.md](../reviews/17-code-review.md). Availability no longer re-runs recovery on every Settings or thumbnail refresh.

- **Integration:** `integrate/17` fast-forwarded `main` to `43b93ae`. Corrupt, unknown-migration, and permission-denied open failures plus recover-after-repair are seam 1. Root `swift test`: 252 tests in 37 suites passed. Unsigned x86_64 `xcodebuild` succeeded. x86_64 only; arm64 not executed. Coordinator chat after Codex/Other Models limits. Manual notice/folder/VoiceOver remain for Prateek.
