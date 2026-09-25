# 52: Saved edits match the editor (interim)

**What to build:** Until the native renderer lands, the Done, Copy, Save and drag output of an edited capture is rendered in one pass by the same function the editor preview uses. Arrows, labels, Blur and Magnify are then never lost or repeated at strip boundaries (D1, story 82). Only outputs taller than 32,768 px keep the strip path, and DA-6 removes that path in ticket 65. Decision 58 records why this interim stays.

**Blocked by:** 44

**Phase:** 1

**Status:** ready-for-agent

- [x] The D1 test for the save path passes without the known-defect mark, for outputs up to 32,768 px tall.
- [x] The strip-versus-render test stays a known defect for the strip path; ticket 65 retires it.
- [x] The Solid redaction canary tests are unchanged and green.
- [x] Peak memory for an edited 5,120 × 32,768 save is measured and recorded.
- [ ] Live editor row: on a 400×500 image, the arrow at row 450 appears and the label appears once.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: implementer, report

Claude Opus 5.5 (1M context), Claude Code, high effort.

**What changed.** `Frisket/Adapters/PNGBitmapCodec.swift`: `encode(_:edits:)` (the Done path, so Copy, Save, drag and History) and `encode(_: EditorDocument)` now render any output up to `PNGBitmapCodec.wholeRenderMaxHeight` (32,768 px) in one pass with `DocumentRenderer.render`, the editor preview's function, and write it through the existing `StripPNGEncoder`. Taller outputs keep the strip path unchanged. The whole-render path builds its base a strip at a time from one cached ImageIO decode (`decodeInStrips`), releases that image, then renders. Drawing the whole image at once (`decode`) peaked at 2.05 GB on its own at 5,120 × 32,768, because of ImageIO's buffers. No core code changed, and the encoder is the same, so D21 is untouched.

**Tests.**
- `d1DoneDeliversExactlyTheEditorPreview`: wrapper removed; it was red (first difference at row 251; the arrow at row 450 had 0 of 700 ink pixels; the label repeated in rows 256–300), and is now green.
- New `savedEditEqualsTheWholeImageRenderUpTo32768RowsTall`: through `encode(_:edits:)` and `encode(_: EditorDocument)`, the output equals `DocumentRenderer.render` for a 400×500 capture at 2× with a crop, and for a 24 × 32,768 capture (the limit) with a label, arrow, redaction and Blur.
- New env-gated `editedSaveOf5120x32768MeasuresPeakMemory` (`FRISKET_EDITOR_MEMORY_RUN=1 scripts/test-core.sh -c release --filter editedSaveOf5120x32768`). Its fixture PNG is written strip by strip (37.5 MB peak before the save). **Measured peak for an edited 5,120 × 32,768 save (redaction, label, arrow, Blur, Magnify): 1,409,613,824 bytes (1.41 GB) phys_footprint; 9.1 s in release on this Intel Mac.** It asserts < 2 GB.
- `d1StripOutputEqualsTheWholeImageRenderForEveryEditKind` stays wrapped (strip path, ticket 65), so `ci.sh --defects` still lists it. The canary tests are unchanged and green.

**Live.** `editor-arrow-label` in `Tools/LiveHarness/matrix.tsv` is flipped to `pass`: it checks only D1, through Done then Copy. The coordinator runs it.

**Open.** Outputs over 32,768 px still use the strip path with D1 until ticket 65.

