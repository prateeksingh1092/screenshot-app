# 93: History opens on the newest capture (D30)

**What to build:** Opening History (⌘⇧1, the menu or Reveal in History) shows the list scrolled to the top with the newest capture selected, so Copy, Save, Restore and Delete act on it. A capture committed while History is open appears at the top without taking the user's selection away.

**Evidence (2026-09-25, live, `fe7fa6e`, built-in display):** after an area capture was kept, ⌘⇧1 showed the list scrolled down, with the rows from 12:28 in view and an older row selected. The row just captured (12:32) was above the visible area. `HistoryModel.reload` keeps `selected` whenever the old row still exists, and the scroll position stays with it, so History Copy copied an older capture (runs `20260925-122721`, `-123153` and `-123209`). On the external display the row passed only because the older capture was an identical pattern.

**Blocked by:** none

**Status:** ready-for-agent (medium effort)

- [x] `show()` selects the newest row and scrolls to it. A reload while the window is already open keeps the user's selection.
- [ ] Live: `history-copy` passes on both displays. The row must verify the capture it just made, not an identical older one.

## Comments

### 2026-09-25: coordinator, created

Found in the first live run after tickets 79 and 81. Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62).

- **Fix:** the selection rule is `HistoryList.selection(keeping:opening:)` in FrisketCore (this ticket's decision). `HistoryWindowModel.reload(opening:)` applies it; `HistoryWindow.show()` reloads with `opening: true`, which selects the newest row and bumps `scrollRequest`, and the list scrolls that row to the top through a `ScrollViewReader`. `reloadIfVisible` (commits), Delete, Try Again and the drag reload keep the user's row while it exists.
- **Tests:** `HistoryListTests.openingHistorySelectsTheNewestRow` and `aReloadWhileOpenKeepsTheUsersRow`. Red: the rule didn't exist (compile failure; the old rule, keep the row while it exists, is what the first test rejects). Green after the fix. D30 had no `knownDefect` test. The scroll itself is AppKit/SwiftUI and is covered only by the live row.
- **Harness (not run):** `row_history_copy` captures a run-unique size (pattern plus a 2–80 point margin) and checks that History's Copy has exactly that size, then `--verify-full`. `history_newest` no longer clicks the top row, so `history-copy`, `history-save` and `history-delete` rely on History's own selection. `matrix.tsv`: `history-copy` is `D30 pass`.
- **Open:** the live criterion, on both displays.
