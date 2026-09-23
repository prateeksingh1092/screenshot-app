# Ticket 36 implementer

Model: Cursor coordinator chat (Claude Opus 5.5 High). Codex and Other Models
are past included-usage limits.

## Seams

- Seam 2: `DocumentRenderer.forEachStrip` matches `render` on a tall canary.
- Seam 1: Done encodes through `StripPNGEncoder`; a 16×96 canary stays fill
  after Solid redaction.
- Editor: `EditorProxy` (max edge 2048) for the canvas; edits stay in
  document points.
- Opt-in peak: `sh scripts/editor-memory-run.sh`. Release run on this Intel
  Mac: **5120×57,600**, 225 strips, PNG **1,180,425,795** bytes, peak
  physical footprint **586,006,528** bytes, elapsed 16.078 s. Under 2 GB.
  x86_64 only; arm64 not executed.

## What landed

- Strip render (256 rows, one-row halo for effects).
- Strip PNG encode on Done.
- Downsampled editor preview from an ImageIO thumbnail.

Stopped before review. Ticket Status/checkboxes unchanged.
