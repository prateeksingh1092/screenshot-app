# 71: Slow down, and keep what's captured

**What to build:** When a scroll is too fast (an offset of 0.8 viewport or more) or ambiguous, the scrolling capture shows "Slow down" in place and keeps the part already captured. Cancel and Done sit next to the region (story 93).

**Blocked by:** 61, 70

**Phase:** 3

**Status:** withdrawn 2026-09-25 (decision 60: scrolling capture removed)

- [ ] The hint appears on a fast or ambiguous step and clears after a good frame.
- [ ] A single alignment failure keeps the accepted part, and the result never contains a wrong seam.
- [ ] The in-place Cancel and Done are reachable with VoiceOver, and the panel still never takes key.
- [ ] Live flick row: the hint appears, and the result is exact up to the accepted part.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
