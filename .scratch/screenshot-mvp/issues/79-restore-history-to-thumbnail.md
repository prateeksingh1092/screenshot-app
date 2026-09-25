# 79: Restore a History item to a Thumbnail

**What to build:** A History row offers "Restore to Thumbnail". The capture appears as a finalized Thumbnail with Copy, Save, Drag and Copy Text but no Edit, and its timeout doesn't commit it again (story 98, decision 28).

**Blocked by:** 73, 78

**Phase:** 5 (DA-10)

**Status:** ready-for-agent

- [x] A restored capture's Thumbnail status is finalized, and Edit is absent.
- [x] Timeout or dismissal never creates a second History row.
- [x] Deleting the History item closes its restored Thumbnail.
- [ ] The History restore row of the live matrix passes.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62). This ticket's decision is in `decisions.md`.

- **Core:** new `CaptureCommand.restoreFromHistory(id)` and outcome `.restored(revision)`. `CaptureLifecycleCoordinator` looks the row up (`finalizedImage`), records the capture as settled and finalized at History's revision, and inserts it into the stack as a kept card, the path ticket 91 (decision 76) built. No pixels return to memory; Copy, Save, drag and Copy Text read from History; `editable` is false. Leaving it (timeout, Close, swipe, Escape, overflow, quit) takes the kept-card path, which never commits; `.dismiss` is refused as already finalized. Restoring a card that is still listed keeps one card and restarts its timeout. A pending or deleted capture is refused as `unknownCapture`. Diagnostics record `restoreFromHistory`; `Notice.after` shows nothing for `.restored`.
- **App:** the History window gains one row action, "Restore to Thumbnail" (Return). `CaptureSurfaces.restoreFromHistory` runs the command, decodes the card's preview from History's image, and puts it on the pointer's display.
- **Tests (`ThumbnailStackCommandsTests`, through `execute` and `thumbnails()`):** `aRestoredHistoryItemIsAFinalizedThumbnailWithoutEdit`, `leavingARestoredThumbnailNeverAddsASecondHistoryRow` (Close, swipe, Escape, overflow, quit; restored by a fresh coordinator on the same History, as after a relaunch), `restoringTwiceKeepsOneThumbnailAndRestartsItsTimeout`, `deletingARestoredHistoryItemClosesItsThumbnail`, `aPendingCaptureCannotBeRestored`. Red first (the command did not exist), then green. `NoticeTests` now enumerates the new command and outcome.
- **Open:** the live-matrix History restore row (coordinator). Stale `.build` module caches pointing at the ticket-91 worktree were deleted in this worktree only.
