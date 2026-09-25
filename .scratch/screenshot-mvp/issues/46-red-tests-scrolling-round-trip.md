# 46: Red tests: scrolling capture round trip

**What to build:** Tests drive `ScrollingCaptureSession.ingest` the way a real scroll does: a synthetic page is sliced into viewport frames with steady, mid-step and flick steps, uniform bands and repeating content, and the stitched image must equal the page (D3). A 5K Retina frame sequence must not stop on an encoded-byte budget before the pixel cap (D20). The test image factory's repeating frame honours its period.

**Blocked by:** 43

**Phase:** 0

**Status:** ready-for-agent

- [ ] A round-trip test through `ingest` covers steady and mid-step scrolls, uniform bands and repeating content. Each result equals the page exactly.
- [ ] A flick on periodic content either equals the page or is reported as ambiguous. A result that is silently short or wrong fails.
- [ ] The loops from branch `diagnose/red-loops` are ported without the `[DEBUG-d3h]` probes.
- [ ] `repeatedScrollingFrame(period:)` uses its period.
- [ ] D20: a 5,120-px-wide 2× frame sequence reaches the pixel cap without a budget stop.
- [ ] The old `stitch(expectedStep:)` scenario tests, which skip the offset search, are not restored.
- [ ] The red tests are marked as known defects.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
