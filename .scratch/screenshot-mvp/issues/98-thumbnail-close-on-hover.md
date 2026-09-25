# 98: Close × on the Thumbnail (decision 91)

**What to build:** A small × in the Thumbnail's corner, shown while the pointer is over the card and reachable by VoiceOver ("Close thumbnail and keep capture in History"). It uses the existing Thumbnail exit (a pending capture is kept in History). Fix the status text that says "Retry Close" when no Close control exists (`ThumbnailPanel.swift:72-83, 99-121`).

**Blocked by:** none. **Status:** ready-for-agent (medium effort).

- [ ] A coordinator test: the × exit keeps a pending capture in History and closes the card, the same as swipe.
- [ ] The × doesn't overlap the five-button row or the picture, and the glass rule of map.md holds.
- [ ] A live row, `thumbnail-close`, added to the harness (the coordinator runs it).
