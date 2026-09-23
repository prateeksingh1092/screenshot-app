# History contract

`CaptureCommandLayer.execute(.dismiss(revision))` freezes the current unedited
output and returns `.finalized(revision, commit)`. A successful commit releases
pending bytes; a failed dismissal retains them. Duplicate completed dismissals
return `alreadyFinalized`. `historyEntries()` reads finalized entries in date/key
order without creating storage. Delete of a pending capture still discards it.

`CaptureHistory` accepts only `AuthorizedFinalization`, whose initializer is
internal and whose construction is restricted to the coordinator by the static
check. The current unedited output is identical to the selected PNG; no separate
original, editor document, or source frame is persisted. A future editor must
supply its frozen rendered output at this same authorization boundary.
Ticket 26's Done does so: the row and record carry the rendered revision
(2 for a first edit), and a capture already committed by Copy can't be edited.

Copy also finalizes before delivery, reports those outcomes separately, and
retains the commit outcome across delivery retries. A failed clipboard delivery
can be dismissed without inserting another row. A commit failure never prevents
Copy. History deletion commands, recovery UI, retention and quota are later tickets.

After a committed Copy whose delivery fails, discard returns `alreadyFinalized`;
the thumbnail offers Retry Copy and Dismiss, without Delete Capture. Decision 44's
pending discard remains memory-only (ticket 13); finalized deletion through
`deleting`, direct unlink, then row removal belongs to ticket 15. If Copy succeeds
but History fails, an acknowledgment-required notice remains visible before the
thumbnail closes.

## Files and migrations

The app derives `Application Support/<bundle identifier>/History.noindex` from
`AppIdentity`. `HistoryStore` creates it only on authorized finalization and sets
`isExcludedFromBackup`. The tests verify the resulting
`com.apple.metadata:com_apple_backup_excludeItem` attribute (`com.apple.backupd`):
in this sandbox Foundation's getter reports false despite the setter creating
that marker. A real Time Machine check remains manual.

The root contains `history.sqlite` (and SQLite sidecars), `staging/`, `images/`,
and the disposable `thumbnails/` cache. File names use the capture UUID only.
Drag copies live under `staging/drag/` and are not History images. The launch
sweep empties `staging/` recursively, including that directory.
The baseline `history-v1` migration creates the integer primary key, unique
capture identifier, revision, relative image/record/thumbnail locations,
dimensions, logical byte sizes, date, and the two allowed states `finalized` and
`deleting`. Deleting entries are hidden from the public query. The image, record,
and thumbnail each have their own recorded logical size for ticket 16.

The writer uses WAL, `synchronous=FULL`, `fullfsync=ON`,
`checkpoint_fullfsync=ON`, `secure_delete=ON`, and incremental auto-vacuum before
creating the first table. No erase-on-schema-change option is enabled. Append
new migrations; do not edit the shipped baseline. The SQL baseline fixture is a
stable input for future migration tests.

A preflight read uses SQLite's immutable, read-only URI before opening a writer
or modifying directory attributes. Unknown migrations return `unknownMigrations`
without changing files. SQLite's ordinary read-only WAL connection can create
`-shm`; therefore a nonempty WAL or rollback journal is refused as
`recoveryRequired` before opening it. Immutable reads never ignore such a journal. Launch recovery
validates a temporary metadata-only copy (database plus WAL/rollback journal)
before opening the original writer. Unknown migrations, including those only
in WAL, leave the original files unchanged. The copy is removed on exit.
Every existing-root reader, writer and sweep holds the exclusive directory lock.

## Commit points

`HistoryCommitPoint` is the closed fault-injection list. The optional throwing
`commitPoint` callback on the real store runs **after** each named operation:

Ticket 26 distinguishes failures before image writes from interrupted writes:
once an image write has been attempted, a pre-commit failure returns
`recoveryRequired`. The coordinator then refuses further editing of that
revision, because authorized pixels may already exist on disk. Recovery files
and the file-first protocol remain intact; a successful row commit still wins
over later cache errors.

1. `pngStaged`: all PNG bytes written to an exclusive staging file.
2. `pngSynced`: `F_FULLFSYNC` succeeded on the staging PNG.
3. `recordStaged`: the finalization record written to an exclusive staging file.
4. `recordSynced`: `F_FULLFSYNC` succeeded on the record.
5. `imageRenamed`: exclusive atomic rename into `images/<UUID>.png`.
6. `recordRenamed`: exclusive atomic rename beside the image.
7. `directorySynced`: `fsync` succeeded for images, staging, and the root.
8. `rowCommitted`: one History row inserted in one SQLite transaction.
9. `thumbnailCached`: post-commit thumbnail written and its location/size updated.
10. `dragStaged`: a copy of the rendered PNG is written and synced under `staging/drag/`. Fired by `DragStagingLifetime`, after finalization, not by `HistoryStore`.
11. `dragPromiseWritten`: the file-promise write completion has returned. The staging file is deleted only after this and the drag-session end, in either order. A fault leaves the file for the sweep. History's image is not moved or deleted.

Root setup also syncs the root and its parent. The sidecar
`images/<UUID>.finalization.json` contains marker `frisket.finalized.v1`,
`captureIdentifier`, `revision`, `width`, `height`, `imageBytes`, and
`finalizedAt` (Foundation JSON Date encoding, seconds since 2001-01-01).
Recovery validates the marker, identifier, positive revision, finite timestamp,
byte count and decoded dimensions. It forces the pixel provider to decode as
well: ImageIO can otherwise return a header-valid image with corrupt compressed
pixels. Retries never overwrite an existing image.

A fault before the row reports not committed and retains pending bytes. A fault
at or after `rowCommitted` reports committed even if the thumbnail is missing.
Thumbnail failure cannot undo History. Both crash tiers cover every point and assert recovery twice, with public
queries and files as the observable results.

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
queries and finalizations also wait for the startup gate, so they cannot serve
unrecovered History even if called before that task runs. An absent root stays
absent until authorized finalization. The lazy `HistoryStore(root:)` initializer
remains available for fixtures and explicit lifecycle control.

`CaptureCommandLayer.recoverHistory()` forwards through the coordinator to
`CaptureHistory.recover()`, returning a typed `HistoryRecoveryReport` or closed
`HistoryFailure`. The report includes measured logical bytes and the number of
missing-image rows removed. An explicit repeat call rechecks the filesystem;
it does not reuse a cached report. A failure disables History queries/commits
for that store until an explicit successful recovery; capture and delivery
continue. Recovery diagnostics accept only closed events/error codes, never
file paths, identifiers, pixel data or underlying error strings.

The sweep holds a nonblocking exclusive `flock` on an open root directory
before opening SQLite or touching its files. The lock lasts until the store is
released, so another instance cannot sweep or write while the owner is active.
A competing instance receives `rootLocked`; process death releases the lock.
No lock file is created. The store closes SQLite before releasing ownership.
`HistoryStore.close()` provides deterministic shutdown for rebuilds and test
fixtures; a closed store refuses further work. Releasing the store also closes
it, but tests do not rely on Swift ARC scheduling to release the lock.

After migration preflight it empties staging, finishes `deleting` rows, removes
missing-image rows with `missingHistoryImage` diagnostics, validates/adopts
row-less images, discards invalid pairs, removes unreferenced records and
thumbnails, and reconciles stored sizes with real files. Missing disposable
thumbnails become nil/zero; a missing finalization record on an already committed
row counts as zero (the durable row already proves authorization). Database
checkpointing and directory synchronization complete changes before accounting.
Logical usage includes every regular file under the root, including archives,
the database, WAL and SHM when present; directories have no logical byte charge.
An unreadable size fails recovery rather than reporting a partial total.

A clean sweep uses an immutable read and never opens a writer, preserving even
SQLite's bytes on the second run. Locations are validated as canonical
identifier-derived relative names, and links/special files are refused before
reconciliation so the sweep cannot follow them outside the root. Moving the
root needs no row rewrites. A restore to another actual Mac remains a manual
check; the automated test moves the root on this Intel Mac.

## Ticket 16 retention and quota

Call `CaptureCommandLayer.maintainHistory()` at launch, before capture work, and
`maintainHistory(limits:)` when applying Settings. Both preserve an absent root.
The defaults are 30 days and 1,000,000,000 logical bytes; Settings persists days
and decimal MB in bundle-scoped preferences. Each successful finalization runs
an oldest-first sweep ordered by date then integer key, excluding that capture.
A tiny quota can remain exceeded by the protected capture and database overhead;
Settings reports the actual usage and overage.

`history-retention-v1` appends the sweep timestamp, one-time date-normalization
flags, persisted quota event/notice state, and an auxiliary ownership ledger.
The baseline migration and fixture remain unchanged. Usage sums indexed logical
image, finalization-record and thumbnail sizes (including hidden deleting rows),
the auxiliary ledger, and current SQLite/database/WAL/shared-memory file sizes.
Launch remeasures tracked files. Failure blocks subsequent commits until a
successful maintenance pass; Copy and Save retain independent delivery outcomes.
An image plus its record and thumbnail exceeding the quota is refused before
creating History storage, with `captureExceedsHistoryLimit` for presentation.

The auxiliary ledger registers the authorized identifier, relative location and
size before staging, follows exclusive renames, and transfers ownership to the
History row atomically with insertion. It contains metadata, never pixel data.
Interrupted staging/row-less files therefore remain accounted for. Launch
remeasures these ledger entries and reconciles an interrupted rename. It does
not adopt or discard row-less captures: that remains ticket 10's responsibility.
Recovery must remove auxiliary entries when deleting files or adopting a row to
avoid double counting. Recovery archives do not exist in this baseline; their
future owner must extend this inventory when introducing archives, retain their
sizes until export/deletion, and exclude external exports. Files are never owned
merely because they reside beneath the History root.

Age eviction defers when now precedes the newest timestamp or advances more than
the configured window since the previous sweep. A missing sweep uses the newest
stored timestamp as its baseline. Future dates normalize to now once per row;
the flag survives restart. The next stable sweep may resume age eviction.
The normalized date is in SQLite; a recovery adopter must preserve it for an
existing row instead of overwriting it from the original finalization record.
Quota enforcement remains active during age deferral.

Eviction marks `deleting` and the quota event together, checkpoints, unlinks owned
files directly, syncs their directories, removes the row, then checkpoints again.
Deleting rows remain counted until row removal and are resumed before launch
remeasurement. `HistoryEvictionPoint.allCases` is the closed interruption list:
`markedDeleting`, `imageUnlinked`, `recordUnlinked`, `thumbnailUnlinked`,
`directoriesSynced`, `rowRemoved`. Seam-1 tests inject a throw and SIGKILL a test
helper at every point, reopen, run maintenance twice, and compare usage to disk.
This is process-interruption evidence, not a power-loss or hardware durability test.
General outstanding-WAL reconciliation and an exclusive root lock remain ticket 10.

`historyStatus(consumeNotice: true)` returns and durably consumes the pending
quota notice. The last-eviction date remains available for the Settings line.
The app refreshes this presentation after finalization/delivery and on opening
Settings. No screen or clipboard adapter is invoked by these queries.
