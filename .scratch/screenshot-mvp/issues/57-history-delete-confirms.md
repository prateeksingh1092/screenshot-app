# 57: History Delete confirms and always succeeds

**What to build:** Deleting from History, by key or by button, asks for confirmation first. If the capture's Thumbnail is open, Frisket closes it and then deletes. The user never sees "Delete failed. Try again." for a state that retrying can't fix (D10, DA-4, story 91).

**Blocked by:** 47

**Phase:** 1

**Status:** ready-for-agent

- [ ] The D10 test passes without the known-defect mark.
- [ ] The confirmation is the only modal in the flow, and Cancel keeps the item.
- [ ] A failure message either names a cause that retrying can fix or offers no retry.
- [ ] The History Delete row of the live matrix passes.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
