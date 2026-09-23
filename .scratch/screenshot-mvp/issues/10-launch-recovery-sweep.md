# 10: Launch recovery sweep and crash-recovery tests

**What to build:** after a crash or forced quit at any commit point, the next launch leaves History exactly consistent with the files on disk, and running recovery twice changes nothing.

**Blocked by:** 09

**Status:** resolved (tested on `main` at `1e40a4d`; home-folder/other-Mac restore pending)

- [x] The sweep takes an exclusive lock first, empties staging, adopts a row-less image only if its finalization record validates (matching identifier and marker, decodes at recorded dimensions), otherwise discards it.
- [x] Rows whose image is missing are deleted with a logged error code; interrupted deletions are finished; row-less thumbnails are removed; recorded sizes are reconciled with disk.
- [x] Tier 1: a fault injected at each named commit point, rebuild over the same directory, recovery run twice, invariants and size totals match disk.
- [x] Tier 2: a helper executable kills itself at a chosen point, at least one case per point.
- [x] A coverage check fails if a commit point exists without a matching case; later tickets that add points extend the list.
- [ ] History survives renaming the home folder and restoring to another Mac (root-relative paths).

## Comments

### 2026-09-23 — coordinator: resolved

Batch-integrated with ticket 21. Codex review: merge. 144 tests on integrate/10-21.
