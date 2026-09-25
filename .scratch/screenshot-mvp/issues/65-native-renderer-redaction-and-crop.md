# 65: Native Capture renderer: crop and Solid redaction

**What to build:** Done, Copy, Save, drag, History and OCR input of an edited capture all come from one renderer behind `CaptureFlattening.flatten`. It draws crop and Solid redaction into an sRGB CGContext and encodes PNG in memory. In this slice, annotations and effects are still painted by the existing pixel code over the whole image; tickets 66 and 67 replace them. Output taller than 32,768 px is refused before anything is allocated (DA-6). The core may import CoreGraphics, CoreText, ImageIO and Accelerate (DA-1). The interface is the design-it-twice hybrid in the plan's Phase 2.

**Blocked by:** 52, 60

**Phase:** 2

**Effort:** xhigh. Before starting, stop and ask Prateek to switch Claude Code to xhigh (decision 58).

**Status:** ready-for-agent

- [x] The privacy-checklist tests are written first:
  1. integer crop with no resampling;
  2. byte-exact redaction goldens;
  3. effects never read outside their box or under a redaction;
  4. a fixed sRGB working space;
  5. OCR reads only the rendered result;
  6. the original is released on Delete or Close;
  7. the PNG carries no metadata.
- [x] The coordinator takes a `flattener:`, with the production renderer in the app and a `ScriptedFlattener` in tests that replaces the reject-once and loop codecs.
- [x] `outputTooTall` is thrown before any allocation. The scrolling pixel cap and the edited-output cap are both 32,768 px, and the editor memory test is updated to match.
- [x] The repository fence allows CoreGraphics, CoreText, ImageIO and Accelerate in the core, and still bans URL-based image destinations and every other disk I/O.
- [x] If `flatten` is async, the in-progress guard is set before the await.
- [x] The existing Solid redaction canary tests pass unchanged.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62). Choices recorded as decision 64.

- **Renderer:** new `Sources/FrisketCore/CaptureRenderer.swift` with `CaptureFlattening.flatten(_:edits:) throws(RenderFailure) -> Data` and `RenderFailure` (`outputTooTall`, `unreadableCapture`, `encodingFailed`). The crop is copied as whole source pixels into one sRGB CGContext (`.copy`, no interpolation). Redactions, effects and annotations are then painted by `DocumentRenderer.paintEdits`, the same code and snapping as the preview's `render`. PNG is encoded in memory, and every chunk except IHDR/colour/IDAT/IEND is dropped (ImageIO adds eXIf on its own). The 32,768 px cap is checked from the PNG header before decoding.
- **Redaction colour as data (decision 61):** `SolidRedaction.colour`, default black; a colour whose alpha isn't 255 is refused. The fill loop uses each redaction's colour.
- **Coordinator:** `codec:` became `flattener:`; the app passes `CaptureRenderer()`. `flatten` is synchronous, so no guard moved. `ScriptedFlattener` (tests) replaces `RejectOnceCodec`, `LoopCodec` and `RenderedPNGCodec`.
- **Deleted:** the D1 interim (`PNGBitmapCodec`'s strip and whole-render save paths, `wholeRenderMaxHeight`) and `BitmapCodec.encode(_:edits:)`. `PNGBitmapCodec` only serves the preview now.
- **Fence:** the core may import CoreGraphics, CoreText, ImageIO and Accelerate; `CG*/CT*/CF*` URL or filename routes and `url:` are rejected (two new fixtures).
- **Tests:** `CaptureRendererTests` covers checklist items 1–4 and 7, the cap, and preview parity; `CaptureRendererLifecycleTests` covers 5 and 6. All went red against a stub first. `EditorMemoryRunTests` now runs at 5,120 × 32,768 (128 strips). The canary tests are unchanged apart from `codec:` → `flattener:`.
- **D21 is fixed as a side effect:** ImageIO unpremultiplies, so its wrapper is gone. That was ticket 67's criterion.
- **Open:** the scrolling pixel cap no longer exists (decision 60). The opt-in 5,120 × 32,768 memory runs were not re-measured; that is Gate B (67). Live check: redaction and crop rows in the editor.

