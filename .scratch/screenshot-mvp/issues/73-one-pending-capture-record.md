# 73: One Pending capture record, one Thumbnail status

**What to build:** The coordinator keeps one record per capture instead of about 13 parallel collections. `thumbnails()` reports each Thumbnail's public status and the next due time, and the UI applies that status. A finalized Thumbnail is therefore announced as finalized, with the right actions. Drag goes through `deliver()` like every other delivery.

**Blocked by:** 54, 55, 57, 58, 59

**Phase:** 4 (candidate #2)

**Status:** ready-for-agent

- [ ] Thumbnail status assertions at the command test surface replace the planned presenter tests.
- [ ] The accessibility name says pending or finalized, stale Edit and Delete actions disappear after finalization, and the close action works (part of D16).
- [ ] There are no `editing` or `delivering` states.
- [ ] The surfaces drop their shadow copies of arrival order and screens.
- [ ] Every existing lifecycle test stays green.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
