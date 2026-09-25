# 54: A cancelled drag leaves the capture pending

**What to build:** Dragging a Thumbnail or an edited capture finalizes it only when a destination accepts the file promise. A cancelled drag leaves the capture pending, with nothing on disk and nothing in History (D7, DA-3, story 88). The promised file is written from memory, and drag staging on disk is gone, which restores the Pending capture invariant.

**Blocked by:** 47

**Phase:** 1

**Status:** ready-for-agent

- [ ] The D7 test passes without the known-defect mark, and `deliver(.drag)` commits on the promise-written event.
- [ ] Drags neither create nor read a staging directory, and the launch sweep removes leftover drag staging, including the 744 B file on this Mac.
- [ ] A completed drop writes the same bytes as Copy and Save of that revision.
- [ ] The Solid redaction canaries hold for the dragged file.
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
