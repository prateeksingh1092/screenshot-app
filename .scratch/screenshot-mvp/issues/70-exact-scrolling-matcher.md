# 70: Exact scrolling matcher

**What to build:** Scrolling capture reproduces the harness page exactly, as CleanShot does (400/90/90/8). The matcher works like this:

- Vision's translational image registration proposes the offset on downsampled frames;
- a dense pixel score verifies it, and the best score wins;
- a uniform or ambiguous overlap waits for the next frame;
- a sticky header or footer needs agreement across two or more frames.

The stitcher doc describes the result.

**Blocked by:** 64

**Phase:** 3 (O4; scope set at Gate A)

**Effort:** xhigh. Before starting, stop and ask Prateek to switch Claude Code to xhigh (decision 58).

**Status:** ready-for-agent

- [ ] The round-trip tests pass for steady and mid-step scrolls, uniform bands and repeating content. A flick on periodic content is reported as ambiguous, never wrong.
- [ ] The live harness page is exact.
- [ ] The Vision probe leftovers are deleted or made real, and the stitcher doc is rewritten.
- [ ] The reference implementations are read, not copied, and the ticket notes their licences.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
