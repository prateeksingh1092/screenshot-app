# 56: Fixed-size Thumbnails that stack

**What to build:** Every Thumbnail is one fixed size, with the capture aspect-fit inside. New Thumbnails stack evenly without overlapping, up to the stack limit (story 90).

**Blocked by:** 48

**Phase:** 1 (D9 → O10)

**Status:** ready-for-agent

- [ ] Thumbnails of very wide, very tall and square captures have identical frames.
- [ ] Stack positions come from a pure layout function with a unit test: no overlap up to the stack limit, and removing one Thumbnail closes the gap.
- [ ] The stack row of the live matrix passes on both displays.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
