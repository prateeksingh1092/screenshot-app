# 64: Scrolling stitch stopgap and Gate A

**What to build:** Scrolling capture stops silently corrupting pages (D3, story 93). The matcher:

- picks the best-scoring offset over every candidate, using dense rows;
- never infers a sticky header from uniform rows;
- treats near-identical frames as no movement;
- waits for the next frame when an alignment is ambiguous, and on a single failure keeps the part already accepted.

Gate A follows: measure on the harness page and record the scope of ticket 70.

**Blocked by:** 46, 48

**Phase:** 1 (◆ Gate A)

**Effort:** xhigh. Before starting, stop and ask Prateek to switch Claude Code to xhigh (decision 58).

**Status:** ready-for-agent

- [ ] The steady and mid-step round-trip tests pass exactly without the known-defect mark.
- [ ] The periodic-content flick is either exact or reported as ambiguous, never silently short. If it is still red, it stays marked.
- [ ] The live harness-page result is recorded against CleanShot's 400/90/90/8.
- [ ] The Gate A outcome, with numbers, is recorded in `decisions.md`, and ticket 70 is updated to match.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
