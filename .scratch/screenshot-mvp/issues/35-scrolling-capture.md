# 35: Scrolling capture

**What to build:** Prateek starts a scrolling capture, scrolls the page himself while a live preview builds, and gets one tall image as a thumbnail he can copy or keep in History.

**Blocked by:** 09, 34

**Status:** in-progress (branch `ticket/35-scrolling-capture`)

- [ ] Manual scrolling only; no Accessibility permission (decision 32).
- [ ] The pending original is held as compressed strips in memory; frames are released promptly.
- [ ] A new scrolling capture is refused when the global pending-byte budget is exceeded.
- [ ] Reaching the pixel cap or memory budget stops the capture with a clear message; the cap is set from the trial's measurements.
- [ ] The result flows to thumbnail, Copy, and History through the command layer.
- [ ] Peak memory is measured and recorded on this Mac.

## Comments
