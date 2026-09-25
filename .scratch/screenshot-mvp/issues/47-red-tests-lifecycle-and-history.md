# 47: Red tests: Pending capture lifecycle and History

**What to build:** Tests at the command seam reproduce five defects. A cancelled drag commits to History and leaves a staged file (D7). Copy Text on a capture with no text overwrites the clipboard (D8). History Delete fails while the capture's Thumbnail is open (D10). History actions fail after "Try Again" recovery (D19). Delete from History and Copy Text overlap other commands, and quit stops at the first capture it can't finalize (D25).

**Blocked by:** 43

**Phase:** 0

**Status:** ready-for-agent

- [x] D7: a drag session that ends without a promise write leaves no file on disk and no History row. It uses the real drag lifetime, not the fake that always fires both events.
- [x] D8: Copy Text with an empty recognition result leaves the clipboard's change count and contents unchanged.
- [x] D10: deleting a History item whose Thumbnail is open succeeds and closes that Thumbnail.
- [x] D19: after History recovery succeeds, `delete` and the finalized image return results rather than `.unavailable`.
- [x] D25: Delete from History and Copy Text take the in-progress guard like every other command. Quit finalizes every capture it can and reports the rest.
- [x] Each is marked as a known defect.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: implementer, report

Claude Opus 5.5, Claude Code, medium effort. Branch `ticket/47-red-tests-lifecycle-and-history`. No product code changed.

**Tests.** All run at the command seam (`CaptureCommandLayer`) and are wrapped in `knownDefect`. Each demonstrating expectation names its defect.

| Test | File | Seam and stand-ins | Red because |
|---|---|---|---|
| `d7CancelledDragLeavesTheCapturePendingWithNothingOnDisk(kind:)` (area, full screen) | `DragHandoffTests` | Real `HistoryStore` and real `DragStagingLifetime`. A `CancellingDragHandoff` does what `FilePromiseDragAdapter` does on cancel: session ends, no promise write, `.failed` | A History row is committed, and the root holds `history.sqlite*`, `images/…png/.json`, `thumbnails/…` and `staging/drag/<uuid>.png`. The capture does stay pending |
| `d8CopyTextWithNoTextLeavesTheClipboardUnwritten` | `RecognizedTextCommandsTests` | Recognizer returns `""`; recording text clipboard | The text clipboard received `[""]` |
| `d8CopyTextWithNoTextLeavesTheSystemClipboardUnchanged` | `RecognizedTextAdapterTests` (new `RecognizedTextClipboardTests` suite) | Real `PasteboardAdapter` over a `CountingPasteboard` whose change count moves on replace | Change count went 11 → 12, and 1 replacement |
| `d10DeletingAHistoryItemClosesItsOpenThumbnailAndDeletes(state:)`: after Done, and after a committed Copy whose clipboard write failed | `HistoryCommandsTests` | Real `HistoryStore`; a codec stand-in renders a valid PNG | `.deleteHistory` → `.rejected(.alreadyFinalized)`, so the History row, the Thumbnail and the held pixels all remain |
| `d19HistoryRowActionsWorkRightAfterRecovery` | `HistoryCommandsTests` | Real `HistoryStore`: commit, `recoverHistory()` succeeds, then row actions | `historyImage` is nil. History Copy and Delete return `.rejected(.unknownCapture)` |
| `d19HistoryRowActionsWorkAfterRelaunch` | `HistoryCommandsTests` | Commit and `close()`, then `HistoryStore.launch(root:)` over the same root | Same three failures. **New finding:** relaunch has the same cause, not only Try Again. The launch sweep's reconciled fast path never opens the writer, so History rows can't be opened, copied or deleted after every relaunch until something new is committed |
| `d25DeleteFromHistoryTakesTheInProgressGuard` | `CaptureCommandsTests` | In-memory `GatedDeleteHistory` whose delete waits at a gate | History Copy of the capture being deleted succeeds and writes the clipboard, instead of `.rejected(.commandInProgress)` |
| `d25CopyTextIsRejectedWhileACopyOfTheSameCaptureIsInProgress` | `CaptureCommandsTests` | Gated image clipboard | Copy Text runs and writes `"words"` during the in-flight Copy |
| `d25CopyIsRejectedWhileCopyTextOfTheSameCaptureIsInProgress` | `CaptureCommandsTests` | Gated recognizer | Copy runs during the in-flight Copy Text |
| `d25QuitFinalizesEveryCaptureItCanAndReportsTheRest` | `ThumbnailStackCommandsTests` | Real `HistoryStore` with a 1 MB limit. The first capture is a synthetic 700×700 noise PNG (>1 MB); the second is the 2×1 stack PNG | Quit returns only `[.finalized(oversized, .notCommitted(.captureExceedsHistoryLimit))]` and leaves the small capture unfinalized; History is empty |

**Evidence (x86_64 only).**
- `FRISKET_SHOW_DEFECTS=1` over the 10 new tests: 28 issues, all expectation failures at their `Dn:` lines. None is a thrown error or a fixture failure.
- A normal run passes them as known issues.
- `scripts/ci.sh` is green: 302 tests in 46 suites, 36 known issues, and the unsigned build succeeded.
- `scripts/ci.sh --defects` lists d7, d8 ×2, d10, d19 ×2 and d25 ×4 as red (plus d22 from ticket 43).

**For the fix tickets.** These existing tests lock the current behaviour and must change with the fixes:
- `RecognizedTextCommandsTests.copyRecognizedTextAfterDoneUsesTheRenderedRevisionStandIn` expects `texts == ["CANARY", ""]`, which writes the empty string (ticket 55).
- `ThumbnailStackCommandsTests.quitStopsWhenACommitFailsAndLeavesLaterCardsPending` locks stop-at-first-failure (ticket 59).
- `RecognizedTextCommandsTests.staleRevisionResultsAreDroppedAndDoNotWriteTheClipboard` runs Done during an in-flight Copy Text and expects `.edited`. If ticket 59 guards Copy Text with `inProgress`, Done is rejected there. Ticket 59 must choose between rejecting Done during OCR and exempting Done.
- The `DragHandoffTests` drag suite (`dragFinalizesTheRenderedRevisionOnce`, `stagingFileIsRemovedOnlyAfterBothDragEvents`, `failedPromiseWriteKeepsTheHistoryCommit`, `dragFaultLeavesHistoryCommittedAndTheStagingFile`) locks commit-at-drag-start and disk staging (ticket 54).

**Other notes.**
- **Flake:** `HistoryRecoveryTests.tierOneRecoversEveryInterruptedCommitTwice(.recordRenamed)` failed once with `.rootLocked` at load average 15, with other worktrees building. It passed 5/5 alone and on the `ci.sh` rerun. It predates this ticket.
- **Compiler quirk:** inside a `knownDefect` closure, `#expect(try await …, "comment")` doesn't compile ("errors thrown from here are not handled"), and `await` inside a comment interpolation is rejected. Hoist the value into a `let` first.
