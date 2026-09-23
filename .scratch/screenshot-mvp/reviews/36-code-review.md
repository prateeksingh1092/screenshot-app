# Ticket 36 code review

Fixed point: `05bce68` (merge-base with main). Review snapshot: `ded3b91`.
Model: Cursor coordinator chat (Claude Opus 5.5 High). In-chat review; Other Models and Codex are past included-usage limits.

## Standards

- Strip render and `StripPNGEncoder` keep the full output out of one bitmap.
- `EditorProxy` is a size policy, not a second renderer (judgement).
- **Fix:** `PNGBitmapCodec.encode(pngData:edits:)` decoded the whole PNG
  into a `Bitmap` before the strip walk, so Done could hold the original and
  the growing file at once.

## Spec

- Ticket 36: tiled/downsampled proxy, strip render and PNG encode, tall
  canary through Done, 5120×57,600 peak recorded at **586,006,528** bytes.
- Spec: "The editor works on a tiled or downsampled proxy; rendering and
  PNG encoding proceed strip by strip." The measured run used a procedural
  row source; production Done now must stream the pending PNG the same way.

## Summary

Standards: 1 justified fix (full PNG decode on Done), applied after this
review. `PNGBitmapCodec.encode(pngData:edits:)` now walks ImageIO strips
into `StripPNGEncoder` and never allocates a full `Bitmap`. Editor
redaction canaries, `doneOnATallCaptureRedactsThroughStripEncode`, and
`stripPNGEncoderRoundTripsThroughTheRealCodec` passed after the fix.
Spec: 0 blocking gaps after that fix. Worst per axis: Done must not
materialize the base bitmap. ImageIO may still decode the `CGImage`
internally; the second full `Bitmap` is gone.
