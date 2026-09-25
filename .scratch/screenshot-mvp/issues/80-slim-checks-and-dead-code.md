# 80: Slim checks and dead code

**What to build:** The repository checks keep only the six named invariants, run from `ci.sh`:

1. `AuthorizedFinalization` is built only by the coordinator;
2. the app writes nothing outside finalization;
3. storage never receives original pixels;
4. the core does no disk I/O;
5. no event taps or global monitors;
6. no network APIs.

The redundant regex rules, the Snapzy provenance and identity checks are deleted (ticket 87 already removed the stitcher, its fixtures and the Vision probe). So is the dead code: test-only public API, empty functions and files, the unread diagnostics (replaced by `os.Logger` with privacy annotations), and the Snapzy build scripts.

**Blocked by:** 67, 77 (70 withdrawn by decision 60)

**Phase:** 5 (O12, O17)

**Status:** ready-for-agent

- [ ] Each of the six invariants has a passing and a failing fixture.
- [ ] The `ci.sh` run time is recorded before and after.
- [ ] Diagnostics use `os.Logger`, and Frisket writes no log files of its own (decision 25 still holds).

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
