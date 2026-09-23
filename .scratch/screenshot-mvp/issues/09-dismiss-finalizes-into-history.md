# 09: Dismiss finalizes into History

**What to build:** dismissing an unedited thumbnail finalizes the capture into History on disk through the file-first commit protocol, and the thumbnail says "Kept in History".

**Blocked by:** 08

**Status:** ready-for-agent

- [ ] Commit order: PNG to staging, full-fsync, atomic rename into place, fsync the directory, then insert one row in one transaction; a finalization record is written alongside the image.
- [ ] Nothing is written under the root before an authorized finalization request; original pixels are never written (static and seam 1 checks).
- [ ] GRDB over SQLite in WAL mode with full synchronous writes and full-fsync; rows hold an integer key, a unique capture identifier, root-relative locations, dimensions, and logical byte sizes; states are only `finalized` and `deleting`.
- [ ] Baseline migration: incremental auto-vacuum and secure delete; the database is never erased in any configuration; a database with unknown migrations is refused without writes; migration fixtures cover these.
- [ ] The root uses a `.noindex` name and is excluded from backup.
- [ ] Thumbnails are a disposable cache generated after commit.
- [ ] The commit points are named in a closed list for ticket 10.

## Comments
