# 14: Thumbnail outcomes on quit, display, and lock events; auto-dismiss setting

**What to build:** thumbnails behave predictably when the app quits, a display is unplugged, the screen locks, or the app crashes, and Prateek can set auto-dismiss to a delay or to never.

**Blocked by:** 11, 13

**Status:** resolved (tested on `main` at `955092c`; lock and unplug manual pending)

- [x] Quit finalizes unedited thumbnails to History, waiting only for commits the user has authorized.
- [x] Unplugging a display moves its thumbnails to a remaining display.
- [x] Screen lock leaves thumbnails pending.
- [x] A crash loses unedited captures; nothing reaches disk before the user acts (decision 31).
- [x] Settings offers auto-dismiss delays and "never".
- [x] Each outcome is covered by a seam 1 test; display unplug and lock are also in the manual checklist.

## Comments

### 2026-09-23 — coordinator note

Decision 54 plus [54-thumbnail-defaults.md](../reports/54-thumbnail-defaults.md): keep ticket 13's 4-card / 10s working defaults. Settings must persist delay and an explicit `never` state (enum or optional deadline). **Zero seconds must not mean never** — the current implementation schedules expiry at insertion if the delay is zero. "Never" disables timeout only; overflow still finalizes (decision 44). Ticket 32 owns pause-under-focus.

### 2026-09-23 — implementer

Cursor coordinator chat (Claude Opus 5.5 High). Report: [14-implementer.md](../reports/14-implementer.md). Seam 1 covers never vs zero, quit, lock, unplug, crash-writes-nothing, and Settings persist mapping. Manual checklist added, not run. Status/checkboxes unchanged pending review.

### 2026-09-23 — review and fix

In-chat review vs `b04a53c`: [14-code-review.md](../reviews/14-code-review.md). One fix: failed quit unbusies remaining cards.

- **Integration:** `integrate/14` fast-forwarded `main` to `955092c`. Never vs zero, quit, lock, unplug, and crash-writes-nothing are seam 1. Settings persist never and seconds separately. Root `swift test`: 246 tests in 36 suites passed. Unsigned x86_64 `xcodebuild` succeeded. x86_64 only; arm64 not executed. Coordinator chat after Codex/Other Models limits. Manual lock/unplug/Settings persist remain for Prateek.
