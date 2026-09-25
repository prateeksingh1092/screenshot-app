# 54: A cancelled drag leaves the capture pending

**What to build:** Dragging a Thumbnail or an edited capture finalizes it only when a destination accepts the file promise. A cancelled drag leaves the capture pending, with nothing on disk and nothing in History (D7, DA-3, story 88). The promised file is written from memory, and drag staging on disk is gone, which restores the Pending capture invariant.

**Blocked by:** 47

**Phase:** 1

**Status:** ready-for-agent

- [ ] The D7 test passes without the known-defect mark, and `deliver(.drag)` commits on the promise-written event.
- [ ] Drags neither create nor read a staging directory, and the launch sweep removes leftover drag staging, including the 744 B file on this Mac.
- [ ] A completed drop writes the same bytes as Copy and Save of that revision.
- [ ] The Solid redaction canaries hold for the dragged file.
- [ ] Live row: a cancelled drag leaves the Thumbnail pending and History unchanged; a drop on Finder adds exactly one History row.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
