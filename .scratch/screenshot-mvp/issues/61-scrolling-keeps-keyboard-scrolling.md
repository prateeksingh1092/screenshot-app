# 61: The page keeps keyboard scrolling during a scrolling capture

**What to build:** During a scrolling capture, Frisket's panel never takes keyboard focus, so Page Down, Space and the arrow keys scroll the page. Pressing ⌘⇧6 again finishes the capture as Done. Cancel stays reachable with VoiceOver, and Esc works once the user clicks the panel. No global monitors are added (D11, DA-9, story 92).

**Blocked by:** 48

**Phase:** 1

**Status:** ready-for-agent

- [ ] Preview updates never make the panel key.
- [ ] ⌘⇧6 during a scrolling capture means Done; with no scrolling capture running, it starts one.
- [ ] The input-monitoring check stays green.
- [ ] Live scrolling row: Page Down scrolls the pattern page during a capture.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
