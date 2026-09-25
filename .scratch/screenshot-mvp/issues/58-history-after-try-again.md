# 58: History works after Try Again

**What to build:** After History recovery ("Try Again") succeeds, every History row action (Copy, Save, Delete, open) works without waiting for another capture (D19, story 97).

**Blocked by:** 47

**Phase:** 1

**Status:** ready-for-agent

- [x] The D19 test passes without the known-defect mark.
- [x] Running recovery twice in a row leaves History consistent.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: coordinator, note from ticket 47

Ticket 47 found that D19 is wider than "Try Again": after any relaunch, History row actions fail until something new is committed, because the launch sweep never reopens the database for writing (`d19HistoryRowActionsWorkAfterRelaunch`). The fix must cover relaunch too.

### 2026-09-24: coordinator, implemented

- **Implementer:** the coordinator (Claude Opus 5.5, Claude Code, high effort).
- **Cause:** recovery truncates the WAL and then closes the writer (`database = nil`), and a relaunch never opens it. `delete` and `finalizedImage` then refused with `guard let database`.
- **Fix, in `HistoryStore`:**
  - `finalizedImage` reads through `currentEntries()`: the open writer, or else the read-only immutable reader that `entries()` already uses.
  - `delete` uses `writerForExistingHistory()`, which reopens the writer on demand, but only when `history.sqlite` exists. An empty root still gets nothing on disk.
- **Tests:** `d19HistoryRowActionsWorkRightAfterRecovery` and `d19HistoryRowActionsWorkAfterRelaunch` are unwrapped and green. The History suites pass: 61 tests in 13 suites. Running recovery twice is still covered by `tierOneRecoversEveryInterruptedCommitTwice`.
