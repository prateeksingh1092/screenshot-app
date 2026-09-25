# 54: A cancelled drag leaves the capture pending

**What to build:** Dragging a Thumbnail or an edited capture finalizes it only when a destination accepts the file promise. A cancelled drag leaves the capture pending, with nothing on disk and nothing in History (D7, DA-3, story 88). The promised file is written from memory, and drag staging on disk is gone, which restores the Pending capture invariant.

**Blocked by:** 47

**Phase:** 1

**Status:** resolved (tested on `main` at `4775539`; live row waits for an approved install)

- [x] The D7 test passes without the known-defect mark, and `deliver(.drag)` commits on the promise-written event.
- [x] Drags neither create nor read a staging directory, and the launch sweep removes leftover drag staging, including the 744 B file on this Mac.
- [x] A completed drop writes the same bytes as Copy and Save of that revision.
- [x] The Solid redaction canaries hold for the dragged file.
- [ ] Live row: a cancelled drag leaves the Thumbnail pending and History unchanged; a drop on Finder adds exactly one History row.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: coordinator, note from ticket 47

Four existing tests in `DragHandoffTests` lock in committing at drag start and staging on disk. Change them with the fix (found by ticket 47).

### 2026-09-24: coordinator, design for the implementer (DA-3)

The coordinator read the current code and chose this design (decision 57, DA-3):

1. **Commit only on an accepted drop.** In the coordinator's `.drag` command, don't finalize before the handoff. Call `drag.deliver(.copy, …)` first. When it returns `.copied`, finalize through the existing commit caching (`deliveryCommits`, `finalized`, `recoveryRequired`) and mark the capture delivered, as today. When it returns `.failed` (cancelled, or the write failed), commit nothing: the capture stays pending, its Thumbnail stays open, and `automaticExitSuppressed` is set as today. Drags from History (`fromHistory`) are already committed and don't change.
2. **Nothing on disk before authorization.** Delete disk staging. `FilePromiseDragAdapter` already writes the promise file from memory through its `writeCopy` closure, and it returns `.copied` only when that write succeeded and the session ended. Replace `DragCopyStaging`, `DragStagingLifetime.stage` and `DragCopyEventBridge` with a small in-memory `DragCopyEvents` object.
3. **Shrink the core writer.** Keep only the in-core promise writer, because the app may not write files (repository check `capture-memory`). Rename `DragStagingLifetime` to `DragPromiseWriter` in `StorageAdapter`, with just `writePromiseCopy(_:to:)`. Remove the `dragStaging:` parameter from `CaptureCommandLayer` and the coordinator, and update every call site.
4. **Commit points.** Remove `HistoryCommitPoint.dragStaged` and `.dragPromiseWritten`. Update every test that lists commit points; the crash tiers must still cover every remaining point.
5. **Leftovers.** The launch sweep must remove a leftover `staging/drag/` (it already empties `staging/`; add a test with a leftover drag PNG).
6. **Tests:**
   - Unwrap `d7CancelledDragLeavesTheCapturePendingWithNothingOnDisk`.
   - Rewrite the four `DragHandoffTests` that lock in commit-at-drag-start and staging, and the `EditorRedactionCommandsTests` drag cases.
   - Add a test that a completed drop commits exactly one History row, and writes the same bytes Copy delivers for that revision.
7. **Live row:** flip `drag-cancel` in `Tools/LiveHarness/matrix.tsv` to `pass`.

### 2026-09-24: implementer, report

Claude Opus 5.5 (1M context), Claude Code, high effort. Implemented the DA-3 design above.

- **Commit on an accepted drop.** The coordinator's `.drag` calls `drag.deliver(.copy, …)` first and finalizes through the existing commit cache only when it returns `.copied`. A cancelled, failed or thrown drag commits nothing, keeps the capture pending with its Thumbnail open, and suppresses automatic exit. History drags are unchanged.
- **No disk staging.** `DragCopyStaging`, `DragStagingID`, `DragStagingLifetime.stage` and `DragCopyEventBridge` are gone; a no-op in-memory `DragSessionEvents` replaces the bridge. `DragStagingLifetime` became `DragPromiseWriter` (StorageAdapter) with only `writePromiseCopy(_:to:)`. `dragStaging:` is removed from `CaptureCommandLayer`, the coordinator and every call site. `HistoryCommitPoint.dragStaged` and `.dragPromiseWritten` are removed; both crash tiers still cover every remaining point.
- **Where the code forced a different choice:**
  1. `DragOutcome.commit` is now `CommitOutcome?`. A cancelled drag of an uncommitted capture has no truthful `CommitOutcome` value, so it reports `nil` (or the cached commit if an earlier delivery already committed).
  2. The editor drag went through `.done`, which commits before the drag, so a cancelled editor drag (the `drag-cancel` live row) would still add a History row. I added `CaptureCommand.render` / `CaptureCommandOutcome.rendered`: the same render as Done without the commit. `EditorLeave.deliver(_, .drag)` maps to it, and `finishEditing` now executes `leave.command(for:)`. Recorded in decision 58.
- **Tests.** D7 was unwrapped (red: History row plus a `staging/drag` PNG, then green). The DragHandoffTests that locked in commit-at-drag-start and staging were rewritten: `nothingReachesDiskUntilTheDropIsAccepted`, `failedPromiseWriteCommitsNothingAndARetriedDropCommitsOnce` and `aFaultedDragCommitsNothingAndKeepsTheCapturePending`. New tests: `editorDragFinalizesOnlyOnAnAcceptedDrop` (canaries on the dropped file, which `DragPromiseWriter` writes; one History row; the dropped bytes equal the History, Copy and Save bytes), `launchSweepRemovesLeftoverDragStagingAndKeepsHistory` (a 744 B leftover), and an `EditorLeaveTests` case. The EditorRedactionCommands drag cases only lost `dragStaging:`.
- **Docs:** `core-package.md`, `history-storage.md` and `manual-checks/12-drag-handoff.md`. The `drag-cancel` matrix row is flipped to `pass`.
- **Left open (live):** the `drag-cancel` row; a Finder drop adds exactly one History row; the real 744 B file on this Mac is removed by the next launch sweep.


### 2026-09-25: coordinator, integrated

Batch 2 (52, 54, 56). The merge had two conflicts, in `matrix.tsv` and in the tests appended to `EditorRedactionCommandsTests`; both were resolved, keeping both sides. At `4775539`, `ci.sh` is green: 335 tests, 52 known issues. The helper's two design choices are sound and recorded in decision 58: `DragOutcome.commit` is optional, and editor drags use `.render`. The live rows wait for an approved install.
