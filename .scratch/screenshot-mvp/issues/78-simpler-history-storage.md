# 78: Simpler History storage

**What to build:** History still keeps 30 days or 1 GB, but each finalized capture is stored as an atomic PNG write plus one GRDB row at default durability. A launch sweep adopts UUID-named orphan PNGs. The sidecars, the ledger, the full-fsync chain and the flock are gone. Existing History migrates behind a Time Machine-excluded backup, which is deleted after the post-migration check.

**Blocked by:** 74

**Phase:** 5 (DA-4, DA-11)

**Status:** ready-for-agent

- [x] The crash-recovery tests are rewritten for the new commit points (tiers 1 and 2).
- [x] A migration test starts from the current schema with sidecars, and no capture is lost.
- [x] Tests cover orphan adoption and a row whose file is missing.
- [x] The retention and quota tests stay green, and eviction takes one checkpoint per batch.
- [x] Recovery and drag staging no longer share a directory (D24).
- [x] The flock and its 250 ms D27 retry are deleted. Reopening a root right after a close never reports `.rootLocked`, even while other tests start child processes.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: coordinator, note

A second test that fails at random under load: `RetentionCommandsTests.processKillAtEveryEvictionPoint…` returned `.recoveryRequired` once, at a load average of about 11 (ticket 49's run). It passed 8 of 8 runs alone. It is probably the same lock and child-process family as D27. The rewrite in this ticket should remove both.

### 2026-09-25: implementer, report

Claude Opus 5.5, Claude Code, medium effort (decision 62). Recorded as this ticket's decision (`NN. Simpler History storage`) in `decisions.md`.

- **Store:** `HistoryStore` rewritten. Atomic PNG write (`images/<UUID>.partial` renamed to `.png`), one GRDB row at default durability, thumbnail cache afterwards. Commit points are now `imageStaged`, `imageWritten`, `rowCommitted`, `thumbnailCached`. The launch sweep adopts decodable row-less `<UUID>.png` files (revision 1, date from the file), drops rows whose image is missing, and removes stray files and `staging/`. Eviction is one batch: files, then all rows in one transaction, one checkpoint (`filesUnlinked`, `rowsRemoved`). Removed: sidecars, ledger, `deleting` state, staging, the fsync chain, the flock and its D27 retry, `HistoryFailure.rootLocked` and its diagnostic code. `maintain` and `status` now join the launch gate.
- **Migration:** `history-rows-v1`, behind an excluded database backup in `migration-backup/` that is deleted after the in-migration row check and `integrity_check` pass. Queries never write, so an unmigrated database reports `recoveryRequired` until the sweep.
- **Tests:** red first: orphan adoption without a sidecar and "no staging directory" both failed on the old store. New: `HistoryMigrationTests` (sidecar schema fixture `Tests/Fixtures/History/history-v2-sidecars.sql`; failed migration keeps the backup), orphan adoption, missing-image row, stray files, D27 reopen-while-spawning, one-batch eviction, adopted capture counted once. Rewritten for the new points: both crash tiers, the commit-point file layout, eviction interruption (in-process and SIGKILL; D27 `withKnownIssue` wrapper removed), the v1 baseline fixture test (now migrates at recovery). Deleted: the two lock-ownership tests.
- **CI:** `scripts/ci.sh` green twice, 357 tests each.
- **Open / live:** migrating the real History on this Mac at first launch of the new build (check rows, thumbnails and that `migration-backup/` is gone); History window still shows adopted items (no thumbnail cached, it falls back to the full image).
