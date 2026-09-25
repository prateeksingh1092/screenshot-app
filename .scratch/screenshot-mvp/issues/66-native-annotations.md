# 66: Arrows, shapes and labels drawn natively

**What to build:** Annotations are drawn with CoreGraphics strokes and CoreText labels (a pinned font at 18 pt, with smoothing off), on top of Solid redactions as today. A label then keeps every character typed, and an arrow appears wherever it was drawn (D6, D1, story 83).

**Blocked by:** 65

**Phase:** 2

**Effort:** xhigh. Before starting, stop and ask Prateek to switch Claude Code to xhigh (decision 58).

**Status:** ready-for-agent

- [ ] The D6 test and the D1 annotation tests pass without the known-defect mark.
- [ ] Annotations still draw above Solid redactions, so the existing tests stay valid.
- [ ] Annotation goldens use a stated tolerance, and redaction goldens stay exact.
- [ ] The unused label seam (`outputCount`) is deleted.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
