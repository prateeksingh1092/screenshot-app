# 50: Selections keep clicks and keys in Frisket

**What to build:** While the user chooses an area or a window, a click inside the Selection or the window highlight goes to Frisket, never to the app underneath. Keyboard focus stays with the overlay, and Esc always cancels. A Selection that starts on any pixel of a display, including its top row, has an Origin display (stories 85 and 86).

**Blocked by:** 45, 48

**Phase:** 1

**Status:** ready-for-agent

- [ ] Both overlays receive mouse events inside the Selection hole and the window cut.
- [ ] The D14 test passes without the known-defect mark.
- [ ] Live rows on both displays: a click inside the hole doesn't reach the pattern window, Esc cancels after that click, and a top-row pointer starts a Selection.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
