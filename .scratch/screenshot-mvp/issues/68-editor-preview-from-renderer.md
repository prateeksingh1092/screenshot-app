# 68: Editor preview from the Capture renderer

**What to build:** The editor preview is drawn by `CaptureRenderer.preview(...).render(edits)` from the same edits that Done uses. At full size it equals the delivered image, and when downscaled, every block that touches a Solid redaction is exact black (D23, story 82). Rendering runs off the main actor, which only swaps images. The old renderer and its proxy are deleted.

**Blocked by:** 67

**Phase:** 2

**Effort:** xhigh. Before starting, stop and ask Prateek to switch Claude Code to xhigh (decision 58).

**Status:** ready-for-agent

- [x] The D23 test passes without the known-defect mark, and a parity test covers `maxEdge` at or above the output size.
- [x] Editing a 5,120 × 32,768 capture never renders on the main thread; responsiveness is measured.
- [x] The old renderer's public API, the editor proxy, the PNG bitmap codec and the bitmap and document types are deleted.
- [x] Thumbnail decoding runs off the main actor.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5, Claude Code, medium effort (decision 62). This ticket's decision is in `decisions.md`.

- **Changed:** `CaptureRenderer.preview(_:maxEdge:)` returns a `CapturePreview`, and its `render(edits)` paints with the same `EditPainter.paint` as `flatten`. The old `DocumentRenderer.swift` became the internal `EditPainter.swift`, and `EditorDocument.swift` became `DocumentEdits.swift`. Downscaling averages each preview pixel only within its own block. Redactions are mapped from output pixels to every preview pixel they touch, in the redaction's colour. Annotations draw under a scaling transform with glyph quantization off. `EditorWindow` renders off the main actor, one render at a time, and the main actor only swaps images. `CaptureSurfaces` builds the preview and decodes Thumbnails with `@concurrent` functions.
- **Deleted:** `EditorProxy`, `PNGBitmapCodec`, `Bitmap`, `EditorDocument`, `BitmapCodec`, and `DocumentRenderer`'s public API with its strip walk. The names are added to `retired-terms.tsv`.
- **Tests:** D23 was red on the arrow head (8 px floor) and then on the label (glyph quantization); it is now unwrapped and green, at 1× and 2×, and covers a grey redaction too. New tests: preview-equals-delivered parity for every edit kind, at `maxEdge` equal to and above the capture's edge, and with a 2× crop; a canary test at non-integer downscales (the canary and neutral previews are identical, and every block touching a redaction is its colour); preview sizing and refusal; and preview decode timing. The D1 strip tests went with the strip walk. The renderer tests now go through `flatten` (file `EditedOutputTests.swift`). The adapter parity tests use `CapturePreview`.
- **Measured:** open and render times, and preview sizes, are in this ticket's decision.
- **Open:** History's thumbnail loader still decodes synchronously (ticket 78's code). Blur and Magnify are only approximate in a downscaled preview. A cropped output from a capture larger than 2,048 px stays downscaled. Live: open the editor on a full-screen Retina capture, check that the canvas fills in and follows edits without stalls, that labels and arrows sit where they are drawn, and that the redaction edges look crisp.

