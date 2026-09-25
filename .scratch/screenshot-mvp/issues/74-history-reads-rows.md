# 74: History reads rows directly

**What to build:** The History window reads `HistoryStore.rows()` in one query, with lookups by ID, a thumbnail cache and a lazily loaded list, so History stays fast with many items. The pass-through command layer is deleted.

**Blocked by:** 73

**Phase:** 4 (candidate #5)

**Status:** ready-for-agent

- [ ] `CaptureCommandLayer` and the History pass-throughs are deleted.
- [ ] Reloading 1,000 rows costs time in proportion to the rows; the time is measured and recorded.
- [ ] Each History row speaks its label once (part of D16).

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
