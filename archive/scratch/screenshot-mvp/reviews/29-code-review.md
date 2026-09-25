# Ticket 29 code review

Fixed point: `ad7aa9c` (merge-base with main). Review snapshot: `4d6a603`.
Model: Cursor coordinator chat (Claude Opus 5.5 High). In-chat review; Other Models and Codex are past included-usage limits.

## Standards

- `DocumentEffect` is a separate type from Solid redaction and from stroke
  annotations. Fixed 3×3 blur and 2× magnify avoid a user-tunable radius that
  could look like redaction.
- Re-stamping fill after effects is extra work in the renderer (judgement);
  it is the cheapest way to keep covered pixels exact fill after a blur halo.

## Spec

- Ticket 29 / story 43: effects read the redacted composite; overlapping blur
  and magnify cannot reveal a canary. Blur is not offered as a redaction.
- Seam 2 covers magnify, blur average, and overlapping effects over fill.
  Seam 1 canaries cover every delivery output at 1× and 2×.
- Tools have VoiceOver labels and unmodified B/M keys. Manual VO remains.

## Summary

Standards: 0 hard findings. Spec: 0 blocking gaps. Worst per axis: redactions
are stamped twice so leak tests stay exact.
