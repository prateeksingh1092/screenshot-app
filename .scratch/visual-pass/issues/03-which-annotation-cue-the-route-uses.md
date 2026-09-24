# Which annotation cue the route uses

Label: wayfinder:task
Status: resolved
Type: task
Parent: [Frisket visual implementation route](../map.md)

## Question

[What the UX-8 rejection still allows](02-what-the-ux-8-rejection-still-allows.md) found that the rejection forbids neither a plate nor more than one Annotation ink, and requires neither. A color picker stays out of scope for this map.

The route still needs one baked cue. Registration specifies four inks (signal red `#FF3B30`, blue `#0A84FF`, yellow `#FFD60A`, white) and a 1 px halo. The independent plan specifies one red ink, plus weight and a plate, and refused a palette because it read UX-8 as a ban. That ban is not in the record.

Under decision 54, record the cue the builder will use. Do not ask the owner to pick. Say what the choice does to Registration's annotation rasterization seam: keep it, narrow it, or drop it. Solid redaction stays `RGBAPixel(0, 0, 0, 255)` and is not an ink.

## Answer

The route uses one Annotation ink and a plate. The ink is today's signal red, `RGBAPixel(255, 59, 48, 255)`. The plate is a 1-output-pixel white ring, `RGBAPixel(255, 255, 255, 255)`, written around the ink and never sampled from the capture. There is no swatch row, no blue, yellow, or white ink, and no color picker.

The rasterization seam is narrowed, not dropped and not kept whole.

Why this cue, and not the four inks. Both plans already treat the mask as the only loud mark, and both already answer an arbitrary background with a second mark: Registration's halo, the independent plan's plate. That second mark is the shared fix. Four swatches are a palette. UX-8's unadopted amendment was a palette in a picker; "left open" is not evidence for shipping one, and red plus yellow is not the colorblind set that amendment described. The later specialist plan chose one red ink. Its reading of UX-8 as a ban was wrong. Its design reason still matches the principle both documents share. [Where custom Liquid Glass may sit](01-where-custom-liquid-glass-may-sit.md) put the editor on the stock toolbar, which has no need of a swatch cluster. The renderer already writes `255, 59, 48, 255` as `DocumentAnnotation.stroke`. Keeping that ink preserves the existing stroke assertions. The white neighbour is the pixel-contract change.

The plate is Registration's signal halo, and only that pair. Arrow and rectangle keep today's pen, `max(2, Int((2 * scale).rounded()))`, then the 1-output-pixel white ring, with the ink written last. Text uses the same ring. The guide shows that same plate: arrow, shape, and text guides are signal red plus `zoom / displayScale` view points of white, which is one output pixel. Blur and magnify stay `labelColor`, with no plate. Solid redaction's guide stays an unfilled black stroke with a light edge, not this plate, and the fill stays `RGBAPixel(0, 0, 0, 255)`.

What stays from the seam. The app target rasterizes `NSFont.systemFont` at 18 document points into a binary `AnnotationMask`. One mask pixel is one document point. `FrisketCore` stamps that mask by `edits.scale`, including the fractional editor-proxy scale, and does not import AppKit. `outputCount` is `Int((points * scale).rounded())` with no floor of 1. The pen subtracts the crop origin and the strip `rowShift`. The rasterizer stays y-up. Tests pass fixture masks, so a font change cannot change the stamp rules. The 5120×182 proxy case still stamps a 1-pixel em, and Done at scale 2 still stamps 36.

What is cut from the seam. No `AnnotationInk` set of four. No `DocumentAnnotation.ink` switch. No per-ink halo colour. No swatches, no selected-ink ring, and no "Blue ink." hint. `DocumentAnnotation.stroke` remains the signal red. The white plate is a renderer constant, not a second user-facing ink.
