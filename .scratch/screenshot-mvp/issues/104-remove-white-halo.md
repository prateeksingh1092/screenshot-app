# 104: Remove the white halo from annotations (decision 100)

**What to build:** Arrows, lines, shapes and labels draw with no 1-pixel white plate, in the preview and in every output. Outlined and Box labels keep their own outline and box. Solid redaction is unchanged.

**Status:** ready-for-agent (medium effort)

- [x] Preview equals flatten for every mark kind and ink with no plate. Update the golden images and tests that expected the plate (EditPainter, InkPaletteTests, `aShapeIsAnOutlineOnly`), and say which ones changed.
- [ ] Live: the `editor-ink-colour` and `editor-arrow-label` rows still pass.

## Comments

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62). Done on ticket 102's branch; this ticket's decision (shared with ticket 102) records it.

**Changed:** `AnnotationPainter` draws only ink: the plate layer and the redaction stamp that followed it are gone (`EditPainter.paint`, `CaptureRenderer.swift`, `Labels.swift`). Arrows and lines fill their polygons; shapes stroke their outline. Standard labels fill their glyphs. Outlined labels stroke their ink outline, then fill their letters. Box labels fill their box, then their letters. Solid redaction is unchanged, and ink still draws above it. Preview and flatten share the painter, so the existing byte-parity tests (`InkPaletteTests`, `ArrowStylesTests`, `LabelTests`, `EditedOutputTests`) still pass for every kind and ink.

**Goldens and tests changed:** `EditedOutputTests.rectangleOutlineMatchesItsGoldenWithinTwoPerChannel` (the 'p' ring is now capture), `labelIsDrawnInThePinnedFontAboveAWhitePlate` → `labelIsDrawnInThePinnedFontWithNoPlate`, and `LabelTests.eachStyleDrawsItsOwnPixels` (no 1 px Box plate). Only comments changed in `InkPaletteTests.aShapeIsDrawnExactlyInEachInk`, `ArrowStylesTests` and `CaptureRendererTests.aShapeIsAnOutlineOnly`: they never asserted plate pixels. New: `SharpnessTests.annotationsDrawWithNoWhitePlate`, red before the change: no pixel lighter than the ink around an arrow, a line, a shape or a Standard label on black, and nothing outside a Box label's box.

**Open:** the live rows `editor-ink-colour` and `editor-arrow-label`. `beta-matrix.sh` line 706's comment mentions the plate's antialiased edge; the row's meter may need recalibrating on its next live run.
