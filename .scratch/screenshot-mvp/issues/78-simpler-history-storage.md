# 78: Simpler History storage

**What to build:** History still keeps 30 days or 1 GB, but each finalized capture is stored as an atomic PNG write plus one GRDB row at default durability. A launch sweep adopts UUID-named orphan PNGs. The sidecars, the ledger, the full-fsync chain and the flock are gone. Existing History migrates behind a Time Machine-excluded backup, which is deleted after the post-migration check.

**Blocked by:** 74

**Phase:** 5 (DA-4, DA-11)

**Status:** ready-for-agent

- [ ] The crash-recovery tests are rewritten for the new commit points (tiers 1 and 2).
- [ ] A migration test starts from the current schema with sidecars, and no capture is lost.
- [ ] Tests cover orphan adoption and a row whose file is missing.
- [ ] The retention and quota tests stay green, and eviction takes one checkpoint per batch.
- [ ] Recovery and drag staging no longer share a directory (D24).
- [ ] The flock and its 250 ms D27 retry are deleted. Reopening a root right after a close never reports `.rootLocked`, even while other tests start child processes.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: coordinator, note

A second test that fails at random under load: `RetentionCommandsTests.processKillAtEveryEvictionPoint…` returned `.recoveryRequired` once, at a load average of about 11 (ticket 49's run). It passed 8 of 8 runs alone. It is probably the same lock and child-process family as D27. The rewrite in this ticket should remove both.
