<!-- Provenance: Cursor Claude Opus 5.5 High subagent 3f6a5555-a98c-47eb-8ad4-466e20029e9d, round 1, 2026-09-22. Final response saved by the facilitator. Official URLs cited from reference knowledge, not fetched this session. -->

## Data and persistence architect: round 1

### Findings

**DATA-1: Ownership must be structural, not inferred from paths**
- Target: decisions 5, 18, 20
- Attack: Snapzy decides app ownership by path prefix. An export folder inside the app folder, or a symlink into it, makes retention treat exports as app-owned. Quick Access Save moves the file and repoints the row at the export, so history no longer owns a copy and history deletion trashes the export.
- Severity: blocker
- Evidence: `TempCaptureManager.swift:263-267`; `CaptureHistoryStore.swift:313-341`; history research §4, §7.
- Amendment: Owned files are addressed only by capture UUID under one root (`images/<uuid>.png`, `thumbs/<uuid>.jpg`); no owned-path column. Save, Save As and drag copy out, never move. Exports never get rows that can trigger deletion. The deleter resolves real paths and refuses anything outside the root. Settings rejects an export folder inside the root. Tests: export folder inside root, symlinked export, and history deletion after Save all leave exports byte-identical.
- Changes an accepted product decision: no

**DATA-2: Define the commit protocol; the database is the source of truth**
- Target: gap (18, 23)
- Attack: Snapzy updates rows and files separately (e.g. `markFileChanged` updates the row, then deletes previews). Its thumbnail orphan sweep compares `<UUID>-preview-v2-…` filenames against bare UUIDs, apparently deleting every current thumbnail per sweep (inference). On macOS, `fsync` does not flush the drive cache.
- Severity: blocker
- Evidence: `CaptureHistoryStore.swift:392-420`; `CaptureHistoryRetentionService.swift:229-235` vs `HistoryThumbnailGenerator.swift:331-335`; https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fsync.2.html
- Amendment: Commit order: write `staging/<uuid>.tmp`, `F_FULLFSYNC`, rename to `images/<uuid>.png`, then insert the row in one transaction. Thumbnails are a disposable cache generated after commit, keyed by UUID. Launch sweep: empty `staging/`; adopt row-less files in `images/` if they decode; delete rows whose image is missing; finish unfinished deletions; remove row-less thumbnails. Kill-injection test per step.
- Changes an accepted product decision: no

**DATA-3: No "pending" state in the schema**
- Target: decisions 16, 20
- Attack: Decision 16 keeps pending captures in memory; a persisted pending state invites writing pixels before finalization.
- Severity: major
- Evidence: inference; history research §Invasiveness proposes pending/committing/finalized states.
- Amendment: States `finalized` and `deleting` only. Deletion: mark row `deleting` (hidden from UI, still counted), unlink files, delete row; recovery resumes. Lint/test: no code path writes under the root before finalization.
- Changes an accepted product decision: no

**DATA-4: Define "bytes" for the 1 GB limit**
- Target: decision 18
- Attack: APFS clones and compression make allocated size unpredictable. SQLite `-wal` grows until checkpoint; deleted pages remain without vacuum. Snapzy records size 0 on read failure. Database recovery archives stay in the folder forever. A single >1 GB scrolling capture could make eviction loop.
- Severity: major
- Evidence: `CaptureHistoryStore.swift:563-575`; `DatabaseManager.swift:280-291`; https://www.sqlite.org/wal.html
- Amendment: Usage = recorded logical sizes (`st_size`) + current database, `-wal`, `-shm` sizes. After each retention run, truncating checkpoint and incremental vacuum. Re-measure at launch and correct drift. A failed size read blocks the commit rather than recording 0. Recovery archives counted, or kept outside the root with a visible prompt. Eviction stops once only the just-committed item remains.
- Changes an accepted product decision: no

**DATA-5: Retention robust to clock changes and ties**
- Target: decisions 5, 18
- Attack: Snapzy compares against wall clock and trims in separate read/write transactions. Clock forward purges everything at launch; clock backward makes new captures look older than future-dated ones. Equal timestamps have no defined order.
- Severity: major
- Evidence: `CaptureHistoryStore.swift:480-487`, `516-535`.
- Amendment: Capture time as UTC epoch seconds; 30 days = 30 × 86,400 s. Evict by monotonic insertion sequence. Future-dated rows treated as captured now. Age and byte passes in one transaction marking rows `deleting`. Tests: clock jumps both ways, time-zone change, equal timestamps.
- Changes an accepted product decision: no

**DATA-6: Migration discipline and schema choices in release one**
- Target: decisions 13, 20
- Attack: Snapzy debug builds set `eraseDatabaseOnSchemaChange`; Prateek will likely use debug builds daily and any migration edit would wipe history. `auto_vacuum` only applies before the first table. FTS5 external-content needs an integer rowid. An older build opening a newer database could misbehave.
- Severity: major
- Evidence: `DatabaseManager.swift:178-181`; https://www.sqlite.org/pragma.html#pragma_auto_vacuum; https://www.sqlite.org/fts5.html#external_content_tables
- Amendment: Never erase the database in any configuration. Create with `auto_vacuum=INCREMENTAL`, `secure_delete=ON`. `INTEGER PRIMARY KEY` plus unique `uuid`. Shipped migrations are never edited; upgrade tests from a fixture database of every past version. A database with unknown migrations is refused without writes. Root folder keyed by the final bundle identifier.
- Changes an accepted product decision: no

**DATA-7: Backup, restore, and moving history**
- Target: decision 20
- Attack: Snapzy stores absolute paths that break on home-folder rename or restore to a new Mac. Time Machine can restore database and images out of step. Copying `.db` without `-wal` loses commits. Backups keep "deleted" history.
- Severity: minor
- Evidence: `CaptureHistoryRecord.swift:32`; `CaptureHistoryStore.swift:579`.
- Amendment: Store only UUIDs and root-relative paths. Launch sweep after restore. Any "export history" uses SQLite backup API or `VACUUM INTO`. Document that deleting history does not remove it from backups.
- Changes an accepted product decision: no

**DATA-8: A persisted OCR index is a separate privacy decision**
- Target: gap (23, 25)
- Attack: Stored OCR text is a searchable plaintext copy of every visible secret; FTS5 shadow tables and WAL frames retain it until overwritten; it counts toward 1 GB.
- Severity: minor
- Evidence: https://www.sqlite.org/pragma.html#pragma_secure_delete; inference.
- Amendment: No OCR table in v1. A later index arrives by migration, built only from the rendered result, deleted in the same transaction as its row, with `secure_delete` and an explicit opt-in decision.
- Changes an accepted product decision: no

**Portable from Snapzy (decision 13):** keep the typed-error database opening with archive-based recovery (`DatabaseManager.swift:61-83, 256-298`), per-process test database isolation (`152-161`), and `ValueObservation` for the history list (`CaptureHistoryStore.swift:51-86`). Do not keep its schema, cloud table, retention service, path-based ownership check, or thumbnail sweep.

### Keep
- Decision 16: memory-only originals remove a whole class of persisted-original recovery.
- Decision 18: enforce after every commit and at launch; never evict the just-committed item.
- Decision 20: versioned migrations and lifecycle state from the first release.

### Questions only Prateek can answer
1. Exclude history from Time Machine (better privacy, but history is lost on disk failure)?
2. Does v1 need "move/export all history", or only per-item export?
3. Should OCR text ever be persisted for search?
