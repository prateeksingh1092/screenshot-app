# Ticket 28 implementer

Model: Cursor coordinator chat (Claude Opus 5.5 High). Codex and Other Models
are past included-usage limits.

## Seams

- Seam 2: `DocumentRenderer.render` for rectangle outline, Bresenham arrow,
  closed 5×7 text, and annotations above redactions.
- Seam 1: Done with a rectangle annotation plus Solid redactions, then
  History, thumbnail, Copy, Save, and drag.

## What landed

- `DocumentAnnotation` is a separate type from Solid redaction. Stroke is a
  fixed opaque colour; there is no opacity, radius, or fill.
- Renderer draws annotations after redactions with copy blend. Text uses a
  built-in 5×7 font so seam 2 stays pixel-exact without CoreText.
- Editor tools: Arrow (`A`), Shape (`S`), Text (`T`), plus a VoiceOver-labelled
  label field. Close-without-changes requires no annotations.

Stopped before review. Ticket Status/checkboxes unchanged.
