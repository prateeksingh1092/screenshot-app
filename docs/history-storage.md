# History contract

`CaptureLifecycleCoordinator.execute(.dismiss(revision))` freezes the current unedited
output and returns `.finalized(revision, commit)`. A successful commit releases
pending bytes; a failed dismissal retains them. Duplicate completed dismissals
return `alreadyFinalized`. `HistoryStore.entries()` reads finalized entries in date/key
order without creating storage. Delete of a pending capture still discards it.

`CaptureHistory` accepts only `AuthorizedFinalization`, whose initializer is
internal and whose construction is restricted to the coordinator by the static
check. The current unedited output is identical to the selected PNG; no separate
original, editor document, or source frame is persisted. A future editor must
supply its frozen rendered output at this same authorization boundary.
Ticket 26's Done does so: the row carries the rendered revision
(2 for a first edit), and a capture already committed by Copy can't be edited.

Copy also finalizes before delivery, reports those outcomes separately, and
retains the commit outcome across delivery retries. A failed clipboard delivery
can be dismissed without inserting another row. A commit failure never prevents
Copy. History deletion commands, recovery UI, retention and quota are later tickets.

After a committed Copy whose delivery fails, discard returns `alreadyFinalized`;
the thumbnail offers Retry Copy and Dismiss, without Delete Capture. Decision 44's
pending discard remains memory-only (ticket 13); finalized deletion unlinks the
files, then removes the row (ticket 15, simplified by ticket 78). If Copy succeeds
but History fails, an acknowledgment-required notice remains visible before the
thumbnail closes.

## Files and migrations

Ticket 78 (DA-4 and DA-11) replaced the sidecar store. A finalized capture is one
atomic PNG write plus one GRDB row at SQLite's default durability. There is no
lock, no staging directory, no finalization sidecar, no ownership ledger and no
`F_FULLFSYNC` chain.

The app derives `Application Support/<bundle identifier>/History.noindex` from
`AppIdentity`. `HistoryStore` creates it only on authorized finalization and sets
`isExcludedFromBackup`. The tests verify the resulting
`com.apple.metadata:com_apple_backup_excludeItem` attribute (`com.apple.backupd`):
in this sandbox Foundation's getter reports false despite the setter creating
that marker. A real Time Machine check remains manual.

The root contains `history.sqlite` (and SQLite's `-wal`/`-shm`; macOS keeps an
empty `-wal` after close), `images/<UUID>.png` and the disposable
`thumbnails/<UUID>.png` cache. File names use the capture UUID only; a row stores
no location, because both are derived from its identifier. Drags stage nothing
on disk (ticket 54, DA-3), so nothing shares a directory with recovery (D24).

Migrations, never edited once shipped: `history-v1`, `history-retention-v1`,
and `history-rows-v1`. The last rebuilds `history` with one row per finalized
capture (identifier, revision, dimensions, image and thumbnail sizes, date and
the date-normalization flag), drops rows the old store was deleting and drops
the ledger table. Its own check rolls it back unless every finalized row
survives with a canonical identifier; then `PRAGMA integrity_check` must pass.

Existing History migrates behind a backup: before `history-rows-v1` runs, the
store copies the database (GRDB `backup(to:)`) into `migration-backup/`, which is
inside the excluded root and excluded itself. It unlinks the files of rows the
old store was deleting, so the sweep can't adopt them back. After the checks
pass it removes `staging/` and every `*.finalization.json`, then deletes the
backup. A failed migration leaves the old database and the backup in place, and
History reports `unavailable`.

The writer uses WAL, `secure_delete=ON` and incremental auto-vacuum before the
first table, and no durability PRAGMAs. No erase-on-schema-change option is
enabled. A preflight read uses SQLite's immutable, read-only URI before opening a
writer or modifying directory attributes. Unknown migrations return
`unknownMigrations` without changing files. A nonempty WAL or rollback journal is
refused as `recoveryRequired` before an immutable read. A query never writes: a
database that still needs a migration also reports `recoveryRequired` until the
launch sweep runs. Launch recovery validates a temporary metadata-only copy
(database plus WAL/rollback journal) before opening the original writer.

## Commit points

`HistoryCommitPoint` is the closed fault-injection list. The optional throwing
`commitPoint` callback on the real store runs **after** each named operation:

1. `imageStaged`: all PNG bytes written to `images/<UUID>.partial`.
2. `imageWritten`: renamed to `images/<UUID>.png` (the atomic write).
3. `rowCommitted`: one History row inserted in one SQLite transaction.
4. `thumbnailCached`: the thumbnail written and its size recorded.

Once an image write has been attempted, a failure before the row returns
`recoveryRequired` (the partial file is removed). The coordinator then refuses
further editing of that revision, because its authorized pixels may already be
in `images/`. A fault at or after `rowCommitted` reports committed even if the
thumbnail is missing. A committed row's image is never replaced.

Both crash tiers cover every point (tier 1 throws in-process; tier 2 kills the
`HistoryCrashHelper` process) and assert recovery twice, with public queries and
files as the observable results. A crash at `imageStaged` loses only the partial
write; from `imageWritten` on, the capture is in History after the next sweep.

## Static guard scope

The `capture-memory` check now rejects app filesystem write routes, constructing
finalization capabilities outside the coordinator, constructing them in capture,
eager storage initializers/properties/queries, and source/original pixel types in
storage. Storage only accepts the authorized output. Accepted and rejected
fixtures cover the additions. This is a conservative lexical guard, not proof
against indirect or deliberately obfuscated writes. Later export adapters need
an explicit, reviewed exception; pending originals must remain memory-only.

## Launch recovery interface

The app injects `HistoryStore.launch(root:)`. It schedules exactly one sweep;
queries, finalizations, maintenance and status also wait for the startup gate, so
they cannot serve unrecovered History. An absent root stays absent until
authorized finalization. The lazy `HistoryStore(root:)` initializer remains for
fixtures and explicit lifecycle control.

`HistoryStore.recover()` returns a typed `HistoryRecoveryReport` (logical bytes
and the number of rows removed because their image was missing) or a closed
`HistoryFailure`. A repeat call rechecks the filesystem. A failure disables
History queries and commits for that store until a successful recovery; capture
and delivery continue. `availability()` surfaces the outcome for Settings and the
History window. Diagnostics carry only closed events and error codes.

The sweep:

1. Refuses links and special files anywhere under the root before touching it.
2. Returns without opening a writer when the database is current and every file
   matches its row, so a clean second sweep leaves every byte unchanged.
3. Otherwise opens the writer (migrating if needed), removes `staging/` and any
   leftover `migration-backup/`, and drops each row whose image is missing (with
   the `missingHistoryImage` diagnostic) along with its thumbnail. Row sizes
   follow the files; a missing thumbnail becomes size zero.
4. Adopts each row-less `images/<UUID>.png` whose pixels decode: size and
   dimensions from the file, date from its modification date, revision 1 (the
   file carries no revision). Anything else in `images/` or `thumbnails/` that no
   row owns is removed. Other files under the root are left alone but counted.
5. Checkpoints and closes the writer. Row actions reopen on demand (D19).

There is no directory lock (DA-11). Two stores on one root are safe at the
SQLite level; the worst case is a sweep in one adopting the other's image just
before its row, which that commit then reports as `recoveryRequired`.
`HistoryStore.close()` gives deterministic shutdown; a closed store refuses
further work. Moving the root needs no row rewrites.

## Retention and quota

Call `HistoryStore.maintain(limits: nil)` at launch and `maintain(limits:)` when
applying Settings. Both preserve an absent root. The defaults are 30 days and
1,000,000,000 logical bytes; Settings persists days and decimal MB. Each
successful finalization runs the same enforcement, excluding that capture. A tiny
quota can remain exceeded by the protected capture and database overhead.

Usage is the recorded image and thumbnail sizes plus the current SQLite files.
Maintenance remeasures every row from its files first; a missing image fails
maintenance and blocks commits until a sweep drops the row. An image plus its
thumbnail exceeding the quota is refused before creating History storage, with
`captureExceedsHistoryLimit`.

Enforcement builds one batch: rows past the age window (unless age eviction is
deferred), then the oldest rows, by date then key, until usage fits. Eviction
records the quota event, unlinks each image then its thumbnail, removes every
row in one transaction, then checkpoints once for the batch.
`HistoryEvictionPoint` (`filesUnlinked`, `rowsRemoved`) is the closed
interruption list. Files go before rows, so a crash leaves rows whose image is
missing, which the sweep drops; never an orphan PNG it would adopt back.

Age eviction defers when now precedes the newest timestamp or advances more than
the configured window since the previous sweep. A missing sweep uses the newest
stored timestamp as its baseline. Future dates normalize to now once per row;
the flag survives restart. Quota enforcement stays active during age deferral.
`status(consumeNotice: true)` returns and consumes the pending quota notice.
