# 09: Dismiss finalizes into History

**What to build:** dismissing an unedited thumbnail finalizes the capture into History on disk through the file-first commit protocol, and the thumbnail says "Kept in History".

**Blocked by:** 08

**Status:** resolved (tested on main at `02b2864`; manual criteria pending per decision 49)

- [x] Commit order: PNG to staging, full-fsync, atomic rename into place, fsync the directory, then insert one row in one transaction; a finalization record is written alongside the image.
- [x] Nothing is written under the root before an authorized finalization request; original pixels are never written (static and seam 1 checks).
- [x] GRDB over SQLite in WAL mode with full synchronous writes and full-fsync; rows hold an integer key, a unique capture identifier, root-relative locations, dimensions, and logical byte sizes; states are only `finalized` and `deleting`.
- [x] Baseline migration: incremental auto-vacuum and secure delete; the database is never erased in any configuration; a database with unknown migrations is refused without writes; migration fixtures cover these.
- [x] The root uses a `.noindex` name and is excluded from backup.
- [x] Thumbnails are a disposable cache generated after commit.
- [x] The commit points are named in a closed list for ticket 10.

## Comments

- 2026-09-23, coordinator (Cursor agent): Codex (GPT-6 Astra, high) implemented this ticket and ran the fresh review (verdict fix-then-merge, `.scratch/screenshot-mvp/reviews/09-code-review-codex.md`).
  - One Codex fix pass corrected the Xcode resolver command in `docs/app-build.md`. It also added a History-failure notice that needs acknowledging, and hid Delete Capture after a committed Copy whose delivery failed.
  - GRDB is pinned exactly to 7.11.1 (`b83108d`). Commit points: `pngStaged`, `pngSynced`, `recordStaged`, `recordSynced`, `imageRenamed`, `recordRenamed`, `directorySynced`, `rowCommitted`, `thumbnailCached`.
  - A Codex session (GPT-6 Astra, high) resolved the integration conflicts with tickets 20 and 19. Full-screen captures now also finalize into History.
  - On `main` at `02b2864`: 80 tests passed in 11 suites, and the unsigned Xcode build succeeded on x86_64 macOS 26.7 with Xcode 26.5. arm64 was not executed.
  - Manual criteria pending with Prateek (decision 49):
    - synthetic Dismiss with the "Kept in History" feedback;
    - persistence on Esc and on Quit;
    - VoiceOver announcement;
    - Delete behaviour;
    - actual backup exclusion of the `.noindex` root, checked with `tmutil isexcluded`.
  - 2026-09-23 20:42 CDT: `tmutil isexcluded` reports Excluded for
    `~/Library/Application Support/io.github.prateeksingh1092.frisket.debug/History.noindex`.
    Other ticket 09 manuals remain pending.
