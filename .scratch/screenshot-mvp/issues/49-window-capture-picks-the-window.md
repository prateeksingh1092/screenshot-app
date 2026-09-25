# 49: Window capture picks the window under the pointer

**What to build:** ⌘⇧5 highlights and captures the real window under the pointer, never the cursor, the Dock or a tiny helper window. Foreign floating windows can still be captured. When window capture fails, the message says why (story 84).

**Blocked by:** 45

**Phase:** 1

**Status:** ready-for-agent

- [ ] The D2 tests pass without the known-defect mark.
- [ ] Rejected windows: an empty owning-app bundle ID, a level at or above the Dock, pop-up menu and cursor levels, a side shorter than 32 pt, the Dock, and Frisket itself.
- [ ] Foreign floating windows are still captured ahead of overlapping normal windows.
- [ ] The window row of the live matrix passes on both displays.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
