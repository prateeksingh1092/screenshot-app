# Ticket 27 code review

Fixed point: `226ff32` (merge-base with main). Review snapshot: ticket branch HEAD.
Model: Cursor coordinator chat (Claude Opus 5.5 High). In-chat review; Other Models and Codex are past included-usage limits.

## Standards

- Baseline: canvas `documentSize` stays the crop rectangle in points, while the
  bitmap is the outward-snapped pixel crop (judgement). Tools keep working in
  document space. Pre-crop `NSImage` is cleared before the new frame is assigned.
- `DocumentEdits.crop` is original-space; tools add the current origin. Acceptable.

## Spec

- Ticket 27 / stories 40 and 42: redactions snap outward after crop and scale;
  canaries cover 1×/2×, fractional rectangles, and every delivery output;
  seam 2 has equivalence and a frozen snapshot.
- Pre-crop display frames discarded on refresh after crop.
- Missing vs ticket wording: no separate crop-command in the command layer
  (crop is a document edit, same as redaction). Not blocking.

## Summary

Standards: 0 hard findings. Spec: 0 blocking gaps. Worst per axis: display size
uses the crop rectangle, not the snapped pixel bounds.
