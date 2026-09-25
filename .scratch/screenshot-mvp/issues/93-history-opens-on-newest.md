# 93: History opens on the newest capture (D30)

**What to build:** Opening History (⌘⇧1, the menu or Reveal in History) shows the list scrolled to the top with the newest capture selected, so Copy, Save, Restore and Delete act on it. A capture committed while History is open appears at the top without taking the user's selection away.

**Evidence (2026-09-25, live, `fe7fa6e`, built-in display):** after an area capture was kept, ⌘⇧1 showed the list scrolled down, with the rows from 12:28 in view and an older row selected. The row just captured (12:32) was above the visible area. `HistoryModel.reload` keeps `selected` whenever the old row still exists, and the scroll position stays with it, so History Copy copied an older capture (runs `20260925-122721`, `-123153` and `-123209`). On the external display the row passed only because the older capture was an identical pattern.

**Blocked by:** none

**Status:** ready-for-agent (medium effort)

- [ ] `show()` selects the newest row and scrolls to it. A reload while the window is already open keeps the user's selection.
- [ ] Live: `history-copy` passes on both displays. The row must verify the capture it just made, not an identical older one.

## Comments

### 2026-09-25: coordinator, created

Found in the first live run after tickets 79 and 81. Claude Opus 5.5, Claude Code, medium effort.
