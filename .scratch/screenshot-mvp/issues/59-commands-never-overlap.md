# 59: Commands on one capture never overlap

**What to build:** Delete from History and Copy Text take the same in-progress guard as every other capture command. Quit finalizes every capture it can and reports the ones it couldn't, instead of stopping at the first failure (D25).

**Blocked by:** 47

**Phase:** 1

**Status:** ready-for-agent

- [ ] The D25 tests pass without the known-defect mark.
- [ ] The existing tests that reject duplicate and stale commands stay green.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
