# 85: Arrow styles and lines

**What to build:** Arrows come in Standard (a tapered shaft with a solid head), Curved (a bend handle in the middle; the head follows the curve) and Double styles, and a plain Line tool is added (story 103).

**Blocked by:** 84

**Phase:** 2b (decision 59)

**Status:** ready-for-agent

- [x] Each style renders the same in the preview and the saved output, and has golden tests with a stated tolerance.
- [x] Curved: dragging the middle handle bends the arrow smoothly, and the head follows the tangent.
- [x] The style menu and the line width are in the tool's contextual controls, labelled for VoiceOver.

## Comments

### 2026-09-25: coordinator, created

From decision 59 (Prateek agreed with the CleanShot editor study). Claude Opus 5.5, Claude Code, high effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62). This ticket's decision is in `decisions.md` ("Arrow styles and the Line tool").

- **Core:** `ArrowGeometry.swift` (new) holds `ArrowStyle` (Standard, Curved, Double, Line), `ArrowBend` (the Curved middle handle, relative to the chord) and `ArrowGeometry`, which turns an arrow-kind mark into filled polygons. `DocumentAnnotation` carries `style` and `bend`. `AnnotationPainter` fills those polygons (plate: fill plus a 2 px outline; ink: fill), so the preview and `flatten` draw the same thing. `MarkEditor` gains the `.bend` handle on Curved arrows, `restyleSelection`, `selectionStyle`, curve-following hit-testing and bounds, and the labels "Curved arrow…", "Double arrow…", "Line…"; the undo menu says "Line" for a line.
- **App (thin):** a Line tool (L) after Arrow; an Arrow style menu (Standard, Curved, Double) next to the Line width menu. Both set the active tool's style or width for new marks and restyle the selected mark; both carry VoiceOver labels ("Arrow style", "Line width").
- **Tests:** `ArrowStylesTests` (new, 14 tests): geometry goldens for each style (1e-9), the Curved handle and tangent head, bend drag as one "Resize Arrow" step, restyle, pixel goldens (interior exactly ink, 2 px outside exactly the base), and preview = delivered byte for byte for every style and width at 1× and 2× with a crop and a redaction.
- **Changed tests that locked the old arrow:** `EditedOutputTests.horizontalArrowHasAVisibleHead` (the solid head is narrower than the old wings: rows 0..<15 instead of 0..<12) and `EditableMarksTests.aWiderOrRecolouredArrowIsDrawnInItsInk` (now uses a Line, since a Standard arrow tapers).
- **Open for the live check:** the look of the tapered arrow and the default curve, the handle drag on the canvas, and VoiceOver reading the two menus.

