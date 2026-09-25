# 74: History reads rows directly

**What to build:** The History window reads `HistoryStore.rows()` in one query, with lookups by ID, a thumbnail cache and a lazily loaded list, so History stays fast with many items. The pass-through command layer is deleted.

**Blocked by:** 73

**Phase:** 4 (candidate #5)

**Status:** ready-for-agent

- [x] `CaptureCommandLayer` and the History pass-throughs are deleted.
- [x] Reloading 1,000 rows costs time in proportion to the rows; the time is measured and recorded.
- [ ] Each History row speaks its label once (part of D16).

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62). Decision 71 records the choices.

- **Command layer deleted.** `CaptureLifecycleCoordinator` is the public actor; `execute` records diagnostics. The eight History pass-throughs are gone; the History window, Settings and launch call `HistoryStore` directly. Tests construct the coordinator and read History from the store they inject.
- **Read model.** `HistoryStore.rows()` is one query, newest first, no paths. `thumbnailPNG`, `finalizedImage` and `delete` look one row up by ID. The core `HistoryList` does a reload as that one query, reports whether rows changed (so an unchanged History does not redraw) and loads pictures per visible row, cached by revision (300). The window used to look up every row's thumbnail one at a time, each a full read, and republish the list after every row; the coordinator measured Done at 48 s with ~240 items and History open.
- **Bug found:** `HistoryStore.maintain`/`status` were synchronous, so a direct `await store.status(…)` hit the protocol's `.unavailable` default. Both are now `async`; the Retention tests caught it.
- **Measured (Intel Mac):** `HistoryList` reload of 240 stored rows 2.4 ms (budget 100 ms). Reload plus every row's thumbnail lookup, worst case: 100 rows 0.115 s, 1,000 rows 0.841 s (ratio 7.3 for 10× the rows; `FRISKET_HISTORY_ROWS=1000`).
- **Tests:** `HistoryRowsTests` (rows, by-ID lookups, relaunch, proportional reload) and `HistoryListTests` (240 rows: one query, zero picture lookups; unchanged reload reports no change; one lookup per picture; cache limit; 240-row budget). They were red only in the sense that `rows()` and `HistoryList` did not exist; the old per-row reload was in the app, out of package reach.
- **D16 row label:** each History row is one accessibility element with one label; the picture well is no longer an element. Unticked: live check.
- **Open / live:** time editor open and Done with History open and ~240 items (≤1 s each); VoiceOver on a History row speaks its label once; History thumbnails appear as you scroll; Settings shows usage (the `status` fix).

