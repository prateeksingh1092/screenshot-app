# 98: Close × on the Thumbnail (decision 91)

**What to build:** A small × in the Thumbnail's corner, shown while the pointer is over the card and reachable by VoiceOver ("Close thumbnail and keep capture in History"). It uses the existing Thumbnail exit (a pending capture is kept in History). Fix the status text that says "Retry Close" when no Close control exists (`ThumbnailPanel.swift:72-83, 99-121`).

**Blocked by:** none. **Status:** ready-for-agent (medium effort).

- [x] A coordinator test: the × exit keeps a pending capture in History and closes the card, the same as swipe.
- [x] The × doesn't overlap the five-button row or the picture, and the glass rule of map.md holds.
- [ ] A live row, `thumbnail-close`, added to the harness (the coordinator runs it).

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62).

- **Frisket/ThumbnailPanel.swift:** a hover × (`ThumbnailCloseButton`, small circular bordered `xmark`) is the trailing item of the controls row inside the glass, after a spacer; the five-button row is unchanged and the picture stays an opaque sibling outside the glass. The card's content view is now `ThumbnailHoverView`, whose always-active tracking area (enter, exit, move) sets `ThumbnailModel.pointerOver`, so hovering the picture shows the × too. The × is in the view tree only while shown (or always while VoiceOver runs), and is labelled "Close thumbnail and keep capture in History" ("Close thumbnail" when finalized). It calls `actions.close`, i.e. `ThumbnailExit.close`, the same exit as swipe and Esc. The window's custom action of the same name is unchanged.
- **Status text:** every "Retry Close" / "or Close" line now names the × ("close (×)"); VoiceOver hears "(Close)".
- **Test:** `theCloseButtonKeepsThePendingCaptureInHistoryAndClosesTheCardLikeSwipe` (`.close` and `.swipe`) through `CaptureLifecycleCoordinator.execute`: History gains the capture, the card is unlisted, pixels are released. It was green on first run: the core exit already existed and the ticket had no `knownDefect` test; the new code is the AppKit/SwiftUI control, which package tests can't reach.
- **Live row:** `thumbnail-close` in `matrix.tsv` and `row_thumbnail_close` in `beta-matrix.sh` (uncalibrated, not run).
- **Decision:** this ticket's decision (× placement, hover tracking, AX name).
- **Open:** the coordinator runs `thumbnail-close` live and checks visually that the × fits beside the row on both displays.
