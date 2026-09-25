# 90: The editor is slow to open and Done is slow since the native renderer

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

**Status:** ready-for-agent (medium effort; use the `diagnosing-bugs` skill)

- [ ] A package test times `CaptureFlattening.flatten` and the editor preview render (`DocumentRenderer.render`) for 800 × 1,000 px with one arrow and one label, and fails above a budget: 250 ms each in a debug build, or whatever the measurement supports, recorded in `decisions.md`.
- [ ] The measured cause is named in the report with numbers, and fixed. The delivered-vs-preview byte equality and every Solid redaction test stay exact.
- [ ] Live, checked by the coordinator: on the built-in display the editor opens in 1 s or less, and Done returns a ready Thumbnail in 1 s or less.
