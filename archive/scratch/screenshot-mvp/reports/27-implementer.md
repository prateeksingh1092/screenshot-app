# Ticket 27 implementer

Model: Cursor coordinator chat (Claude Opus 5.5 High). Codex and Other Models
are past included-usage limits.

## Seams

- Seam 2: `DocumentRenderer.render` with `DocumentCrop`, including
  render-equivalence and a frozen snapshot.
- Seam 1: Done with crop, then History, thumbnail, Copy, Save, and drag.

## What landed

- Crop is an optional document edit in original points. Renderer crops first,
  then snaps redactions in the cropped output.
- Editor Crop tool (`C`) composes further crops. The canvas clears the
  pre-crop display image before assigning the new size.
- Canaries at 1× and 2× cover every delivery output.

Stopped before review. Ticket Status/checkboxes unchanged.
