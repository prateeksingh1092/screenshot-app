# 66: Arrows, shapes and labels drawn natively

**What to build:** Annotations are drawn with CoreGraphics strokes and CoreText labels (a pinned font at 18 pt, with smoothing off), on top of Solid redactions as today. A label then keeps every character typed, and an arrow appears wherever it was drawn (D6, D1, story 83).

**Blocked by:** 65

**Phase:** 2

**Effort:** xhigh. Before starting, stop and ask Prateek to switch Claude Code to xhigh (decision 58).

**Status:** ready-for-agent

- [x] The D6 test and the D1 annotation tests pass without the known-defect mark.
- [x] Annotations still draw above Solid redactions, so the existing tests stay valid.
- [x] Annotation goldens use a stated tolerance, and redaction goldens stay exact.
- [x] The unused label seam (`outputCount`) is deleted.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62 supersedes the xhigh note above). Choices recorded as decision 67.

- **Renderer:** new `AnnotationPainter` in `Sources/FrisketCore/CaptureRenderer.swift` draws rectangles and arrows with CoreGraphics and labels with CoreText (`HelveticaNeue-Bold`, 18 pt × scale, antialiased, smoothing off). `DocumentRenderer.paint` calls it, so the preview and `flatten` share it: plates, then the redactions again, then ink above them. The per-pixel stroke, ring and bitmap-font code is gone.
- **Deleted:** `AnnotationFont.swift` and `DocumentRenderer.outputCount`. A label now accepts any non-blank text.
- **Tests:** D6 unwrapped (red: `. $ - %` dropped, lowercase → uppercase; now green). The D1 test is split: redactions + annotations in strips run unwrapped (red: marks differed at strip boundaries; green within the stated tolerance of 32 per channel), and the effects half keeps `knownDefect("D1")` for ticket 67. New: `d1DeliveredAnnotationsEqualThePreviewAndAppearWhereDrawn` (exact, at the `flatten` seam, including the 400 × 500 repro), a rectangle golden (within 2 per channel), and a pinned-font label test.
- **Changed tests that locked old behaviour:** the closed-font label test was replaced; `"!@#"` is now a valid label (blank text is still refused); the annotation canary's outline geometry now matches the inside-the-box stroke.
- **Open:** D1 (effects in strips) and D23 stay known defects (tickets 67, 68). Live: check an arrow, a rectangle and a label `v2.1 $4.99 -10%` in the editor and in the saved file.
