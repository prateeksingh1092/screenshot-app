# 79: Restore a History item to a Thumbnail

**What to build:** A History row offers "Restore to Thumbnail". The capture appears as a finalized Thumbnail with Copy, Save, Drag and Copy Text but no Edit, and its timeout doesn't commit it again (story 98, decision 28).

**Blocked by:** 73, 78

**Phase:** 5 (DA-10)

**Status:** ready-for-agent

- [ ] A restored capture's Thumbnail status is finalized, and Edit is absent.
- [ ] Timeout or dismissal never creates a second History row.
- [ ] Deleting the History item closes its restored Thumbnail.
- [ ] The History restore row of the live matrix passes.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
