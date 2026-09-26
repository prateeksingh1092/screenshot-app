# 102: Captures and labels look softer than CleanShot's (D32)

**What Prateek saw (2026-09-25, acceptance test 83, build `4969168`):**
- Label text on the image is "kinda not crisp" (test 4).
- The same terminal window captured by CleanShot and by Frisket: Frisket's text is visibly softer. The evidence is in `.build/evidence-102/`, kept out of git because it shows Prateek's screen.

**First measurements:**
- CleanShot: 2324 × 1562 px, **144 dpi**.
- Frisket (the clipboard PNG): 3584 × 1972 px, **72 dpi**.
- Frisket keeps Retina pixels but marks them 72 dpi. Viewers that honour dpi show the image at twice its point size and then scale it, which softens the text.

**Hypotheses, to test in this order:**
1. The PNG density (pHYs) is missing or 72 dpi. The fix: write 72 × the backing scale, as CleanShot and `screencapture` do.
2. The capture is resampled: a fractional crop or scale, or ScreenCaptureKit returning a non-native `pointPixelScale` or colour space.
3. Labels are rendered at 1× and upscaled, or font smoothing and hinting is off (decision 84 pins the font).

**Status:** ready-for-agent (medium effort), after the acceptance walkthrough.

- [ ] A test at the flatten and export seam: a Retina capture's PNG carries the display's dpi.
- [ ] A test: a capture's pixels equal the display's pixels 1:1 at native scale, with no resampling.
- [ ] Labels render at output resolution. Compare against CleanShot at 2×.
- [ ] Live: a side-by-side of CleanShot and Frisket on the same synthetic text, at 1× and 2×.
