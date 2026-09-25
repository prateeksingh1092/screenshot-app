# 59: Commands on one capture never overlap

**What to build:** Delete from History and Copy Text take the same in-progress guard as every other capture command. Quit finalizes every capture it can and reports the ones it couldn't, instead of stopping at the first failure (D25).

**Blocked by:** 47

**Phase:** 1

**Status:** resolved (tested on `main`)

- [x] The D25 tests pass without the known-defect mark.
- [x] The existing tests that reject duplicate and stale commands stay green.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: coordinator, note from ticket 47

Two existing tests conflict with the fix. `quitStopsWhenACommitFailsAndLeavesLaterCardsPending` locks in quit stopping at the first failure. `staleRevisionResultsAreDroppedAndDoNotWriteTheClipboard` expects Done to succeed during Copy Text; decide whether Done is rejected or exempted when Copy Text takes the in-progress guard, and record the choice (found by ticket 47).

### 2026-09-24: coordinator, implemented

- **Implementer:** the coordinator (Claude Opus 5.5, Claude Code, high effort).
- **History Delete:** it holds `inProgress` across the store call, so a History Copy of the same capture is rejected until the delete ends.
- **Copy Text:**
  - It first checks every guard, then marks the new `recognizing` set for the whole recognition.
  - Every command guard now checks `isBusy` (`inProgress ∪ recognizing`), except Done, per decision 58. So Copy and Copy Text reject each other.
- **Quit:** it dismisses every Thumbnail in arrival order and returns every outcome. Each capture History refuses stays pending.
- **Tests:**
  - All four D25 tests are unwrapped and green.
  - `quitStopsWhenACommitFailsAndLeavesLaterCardsPending` became `quitTriesEveryCardWhenHistoryIsBlockedAndLeavesThemPending`: both cards are tried, and both stay pending.
  - `staleRevisionResultsAreDroppedAndDoNotWriteTheClipboard` passes unchanged, which confirms that Done still works during Copy Text.
- **CI:** `ci.sh` is green: 321 tests, 77 known issues.
