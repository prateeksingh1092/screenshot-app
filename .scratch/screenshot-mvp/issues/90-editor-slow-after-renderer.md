# 90: The editor is slow to open and Done is slow (cause: the History reload, not the renderer)

**What to build:** Opening the editor and pressing Done are as fast as before tickets 65 and 66, or faster.

**Evidence (2026-09-25, live, built-in display at 2×):** the capture is 400 × 500 pt (800 × 1,000 px), with one arrow drawn, then Done.

| Build | Editor opens | Done → Thumbnail ready |
|---|---|---|
| `2bb1dfe` (before 65) | 0.8 s | 0.5 s |
| `789d460` (65, 66, 73, 89 merged) | 7.2 s | more than 60 s (the Thumbnail never became ready within the wait) |

- **Effect on the harness:** the built-in matrix covered only 9 of its 18 rows in 9 minutes, against all 21 rows in 9 minutes before these merges.
- **External display (1×):** the editor rows still passed, so the cost grows with pixel count or scale.

**Suspects:** these are unverified, so measure before changing anything.
- `AnnotationPainter` or the CoreText path running per pixel or per strip;
- a full-image render on every editor refresh;
- the PNG chunk filter;
- the strip walk (`forEachStrip`), if it is still reached from production.

**Blocked by:** none. It runs before 67, which also changes the renderer.

**Status:** resolved by diagnosis 2026-09-25: the renderer is not slow; the cause is the History reload, fixed in ticket 74

- [x] A package test times `CaptureFlattening.flatten` and the editor preview render (`DocumentRenderer.render`) for 800 × 1,000 px with one arrow and one label, and fails above a budget: 250 ms each in a debug build, or whatever the measurement supports, recorded in `decisions.md`.
- [ ] The measured cause is named in the report with numbers, and fixed. The delivered-vs-preview byte equality and every Solid redaction test stay exact.
- [ ] Live, checked by the coordinator: on the built-in display the editor opens in 1 s or less, and Done returns a ready Thumbnail in 1 s or less.

### 2026-09-25: implementer, report

Claude Opus 5.5, medium effort (decision 62), `diagnosing-bugs` loop.

- **Loop:** `scripts/test-core.sh --filter RenderTimingTests` (new, `Tests/FrisketCoreTests/RenderTimingTests.swift`): 800 × 1,000 px noise PNG (2.8 MB), scale 2, one arrow and one label; budget 250 ms per seam, fastest of three (decision 70).
- **Measured (debug, this Intel Mac):** `DocumentRenderer.render` 2–8 ms; `CaptureRenderer.flatten` 120–130 ms; the whole Done command (`CaptureCommandLayer.execute`, flatten plus History commit) 220–250 ms, also with 240 items in History; the editor-open chain (`ThumbnailImage.make` 18 ms, `bitmap(from:)` 11 ms, render, `PNGBitmapCodec.image` <1 ms). A throwaway probe measured these and was deleted.
- **Cause:** not in the renderer. None of the four suspects costs more than 130 ms, so no product code changed and the test never went red. The live slowness is outside every package seam.
- **Lead for the coordinator (History, ticket 74's area, not touched here):** the failed-row screenshot of run `20260925-024155` shows the History window open, and the live History holds 240 items (the harness keeps its captures). With the window visible, each Copy, Save or Close runs `HistoryWindowModel.reload`, which awaits 240 thumbnail lookups one at a time (1.8 s core-side, measured) and assigns `rows` after each one, so the list re-renders 240 times on the main actor. In that run's `editor-label-text` row, the old, busy Thumbnail was still up after Done ("Copy recognized text" `enabled="0"`).
- **Open:** the live criterion. Time it with the History window closed, then open.


### 2026-09-25: coordinator, live confirmation

On the installed `789d460`, built-in display, with the same capture and steps:

| History window | Editor opens | Done → editor closed | Done → Thumbnail ready |
|---|---|---|---|
| closed | 0.8 s | 0.4 s | 0.5 s |
| open (about 240 items) | 5.8 s | 1.1 s | 48.4 s |

**Correction:** the "before 65" row in this ticket's table was measured just after a relaunch, which had closed the History window. It was never a regression from ticket 65 or 66. The History reload is ticket 74's area; its agent has this evidence, and its live check covers the timing with History open.
