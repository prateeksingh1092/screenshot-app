# 57: History Delete confirms and always succeeds

**What to build:** Deleting from History, by key or by button, asks for confirmation first. If the capture's Thumbnail is open, Frisket closes it and then deletes. The user never sees "Delete failed. Try again." for a state that retrying can't fix (D10, DA-4, story 91).

**Blocked by:** 47

**Phase:** 1

**Status:** resolved (tested on `main`; live row pending the next matrix run)

- [x] The D10 test passes without the known-defect mark.
- [x] The confirmation is the only modal in the flow, and Cancel keeps the item.
- [x] A failure message either names a cause that retrying can fix or offers no retry.
- [ ] The History Delete row of the live matrix passes.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: coordinator, implemented

- **Implementer:** the coordinator (Claude Opus 5.5, Claude Code, high effort).
- **Core:** `.deleteHistory` accepts a finalized capture whose Thumbnail is still open. It deletes the row first. Only on success does it release the Thumbnail and its held pixels (`closeFinalizedThumbnail`), as a Thumbnail exit does. A pending capture is still refused.
- **App:**
  - History Delete asks first: an `NSAlert` whose "Delete" button is marked destructive, plus "Cancel". This is the only modal.
  - After a successful delete, the capture's Thumbnail closes on screen (`CaptureSurfaces.historyDeleted`).
  - Failure text: "busy … Delete again in a moment" for `commandInProgress`, which a retry fixes, and "Could not delete. History is unavailable." otherwise, with no retry offered.
- **Tests:** `d10DeletingAHistoryItemClosesItsOpenThumbnailAndDeletes` covers the states after Done and after a failed Copy. It is unwrapped and green.
- **Live:** the `history-delete` row now expects pass and confirms with Return. It runs in the next matrix run.
