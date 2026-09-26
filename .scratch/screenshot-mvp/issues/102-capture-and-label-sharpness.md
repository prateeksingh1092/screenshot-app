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

- [x] A test at the flatten and export seam: a Retina capture's PNG carries the display's dpi.
- [x] A test: a capture's pixels equal the display's pixels 1:1 at native scale, with no resampling.
- [x] Labels render at output resolution. Compare against CleanShot at 2×.
- [ ] Live: a side-by-side of CleanShot and Frisket on the same synthetic text, at 1× and 2×.

## Comments

### 2026-09-25: coordinator, live

A Frisket window capture of a 1792 × 986 pt window on the built-in Retina display, saved as a file: 3584 × 1972 px, 72 dpi. Its pixels are exactly 2× the points, so hypothesis 2 (resampling) is unlikely. Hypothesis 1 (dpi) is the lead. Test hypothesis 3 (labels) separately.

### 2026-09-25: Prateek, acceptance test 12

"The text quality/appearance is kinda blurry even in the editor, even at the smallest size." Because the blur shows inside the editor too, the dpi marking (hypothesis 1) can't explain all of it. Label rendering (hypothesis 3) is confirmed as a cause and comes first. The white halo is removed by decision 100, which may also help labels look sharper.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62). Done together with ticket 104 on one branch; this ticket's decision records both.

**Root causes, in plain words:**
1. **The editor (the blur inside the editor):** the editor showed a copy of the capture capped at 2,048 px. For a Retina window capture 3,584 px wide, the shrink kept one pixel out of each block and skipped the rest, so 3 of every 7 pixel columns and rows were dropped. The canvas then stretched that 2,048 px copy back up to its own larger size, doubling pixels. Text, captured and labels alike, looked ragged and uneven in the editor at every label size. What was delivered was not affected by this.
2. **The outputs:** every PNG said 72 dpi, because `flatten` stripped the density and the capture sources never wrote one. Apps that honour dpi showed a 2× capture at twice its size and resampled it. CleanShot and `screencapture` write 144 dpi. The pixels themselves were 1:1 with the screen; there was no resampling.
3. **Labels:** they were already drawn at full output resolution, antialiased, on a whole-pixel baseline (the new sharpness test passed before any change). The 1-pixel white plate around every glyph made them look haloed; ticket 104 removes it.

**What changed:**
- `CaptureRenderer.capturePNG(_:scale:)` is the one PNG encoder: pHYs = 72 dpi × the display's scale. The area/full-screen and window sources use it, and `flatten` keeps the capture's density. Clipboard, file, drag and History carry 144 dpi at 2×.
- The editor preview is full resolution for any one-display capture (`previewMaxEdge` 6,016). Where it still downscales, it area-averages, so no column is dropped. The canvas draws it with high-quality interpolation, not nearest-neighbour.
- A live drag renders through a 2,048 px copy (`CapturePreview.reduced()`) to keep the 60 Hz frame, and mouse-up re-renders at full size. Release, 6,016 × 3,384: drag medians 4.7–13.3 ms.
- Ticket 104: no plate; see that ticket.

**Tests:** new `SharpnessTests`. Density at 1×, 2× and 3× for the encoder and through `flatten`, with the pixels 1:1: red before the change. A display-sized capture is previewed at full size: red. A downscaled preview drops no column or row: red. The live preview keeps the redaction blocks. The label baseline is a sharp edge (a guard: already green). No plate on any mark: red. Existing tests changed are listed in this ticket's decision. `scripts/ci.sh` is green.

**Open:** the live side-by-side with CleanShot at 1× and 2× (a live-matrix row). The coordinator should check by eye that the editor canvas looks crisp on the built-in display, and that a drag briefly shows the softer live copy before it snaps sharp on mouse-up.
