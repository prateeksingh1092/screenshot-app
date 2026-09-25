# Ticket 28 code review

Fixed point: `c665f89` (merge-base with main). Review snapshot: `022e6d2`.
Model: Cursor coordinator chat (Claude Opus 5.5 High). In-chat review; Other Models and Codex are past included-usage limits.

## Standards

- Tools repeat the crop-origin offset already used by Solid and Crop (judgement;
  keep the same shape).
- Arrow endpoints use nearest-pixel rounding, not outward snap. Acceptable for
  a stroke, not a coverage fill.
- `DocumentRenderer`’s header still describes crop and redaction only
  (judgement).

## Spec

- Ticket 28 / story 39: arrows, rectangle shapes, and text labels render above
  redactions and appear on every delivery output. Shape is outline-only with a
  fixed opaque stroke; it cannot become a see-through or rounded redaction.
- Seam 2 has a pixel test per annotation type. Seam 1 canaries cover History,
  thumbnail, Copy, Save, and drag.
- Tools have VoiceOver labels and unmodified A/S/T keys. Manual VO remains.
- Spec further-notes mention render-equivalence and a frozen snapshot for
  annotation rendering. Ticket wording asks only for per-type pixel tests;
  those exist. Not blocking.

## Summary

Standards: 0 hard findings. Spec: 0 blocking gaps. Worst per axis: no dedicated
annotation frozen snapshot; arrow rounding is nearest-pixel.
