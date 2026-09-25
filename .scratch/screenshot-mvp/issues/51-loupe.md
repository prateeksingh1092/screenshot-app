# 51: The Loupe while choosing a Selection

**What to build:** The Loupe comes back (D26, stories 6 and 100). While the user chooses an area Selection, a magnified view of the device pixels under the pointer follows the pointer so edges can be placed exactly. The Loupe never appears in the capture.

**Blocked by:** 48

**Phase:** 1

**Status:** ready-for-agent

- [ ] The Loupe shows device pixels around the pointer, with the centre pixel marked, on Retina and 1× displays.
- [ ] It stays on the Origin display and moves aside near display edges so it never covers the pointer.
- [ ] Its pixels come from the same capture source as the Selection, so it never shows Frisket's own overlay.
- [ ] It is hidden before pixels are taken, so no capture contains it.
- [ ] Live row: the Loupe is visible on both displays, and the captured image has no Loupe in it.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
