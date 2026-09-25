# 75: One Region request for every capture mode

**What to build:** Area, full-screen and scrolling capture use one Region request computed in the core, which carries the display ID. `WindowSelection(rows:)` owns the join and filter of window listings. Together they replace the seven-step ordering, the copied scrolling geometry and the display-ID side channels.

**Blocked by:** 49, 50, 72

**Phase:** 4 (candidates #6, #7)

**Status:** ready-for-agent

- [ ] Coordinates are flipped in one place, and displays are looked up in one place.
- [ ] The exclusion regression tests from ticket 45 stay green for every mode.
- [ ] The capture rows of the live matrix stay green on both displays.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
