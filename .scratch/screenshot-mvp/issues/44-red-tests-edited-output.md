# 44: Red tests: edited output and preview

**What to build:** Tests reproduce every known way an edited capture's delivered image differs from what the user saw: arrows, labels, Blur and Magnify lost or repeated at strip boundaries (D1); preview redactions and strokes drawn at the wrong size (D23); a fractional crop leaving a sliver of original pixels beside a Solid redaction (D18); label characters dropped (D6); and dark fringes from premultiplied pixels written as straight alpha (D21). Each is red for its stated reason and marked as a known defect.

**Blocked by:** 43

**Phase:** 0

**Status:** resolved (tested on `main` at `ce152d4`)

- [x] D1: for generated documents with every annotation and effect kind, at several strip heights and image heights from 8 to 2,000 px, the strip output equals the whole-image render.
- [x] D1: the decoded saved output of an edited capture equals the whole-image render, through the save path the app uses.
- [x] D23: at a downscaled preview, each Solid redaction and stroke covers the same area as in the saved output at that scale, not more.
- [x] D18: the test that locks the sliver is corrected. After a fractional crop, no original pixel under a Solid redaction is visible, and the redaction stays aligned with its content.
- [x] D6: a label typed as `v2.1 $4.99 -10%` renders every character, and lowercase differs from uppercase.
- [x] D21: a partly transparent pixel survives save and decode without darkening.
- [x] Each test fails for the reason it names, never because of a fixture error, and is marked as a known defect.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: implementer, report

Claude Opus 5.5, Claude Code, medium effort. Branch `ticket/44-red-tests-edited-output`. No product code changed.

Every test below is wrapped in `knownDefect`. Unwrapped (`FRISKET_SHOW_DEFECTS=1`), each fails only at its `Dn:` expectation; the fixtures and controls are untagged and green.

| Test | Defect | Seam | Why it's red (unwrapped message) |
|---|---|---|---|
| `EditedOutputDefectTests.d1StripOutputEqualsTheWholeImageRenderForEveryEditKind(stripHeight: 7, 64, 256)` | D1 | `DocumentRenderer.forEachStrip` vs `render`. There are 9 seeded documents (heights 8–2,000 px), each with a Solid redaction, rectangle, arrow, label, Blur and Magnify | 17 of 27 cases differ, for example "strip height 256, image height 2000, seed 9: strips differ from the whole render from row 256" |
| `EditedOutputParityTests.d1DoneDeliversExactlyTheEditorPreview` | D1 | `.done` through `CaptureCommandLayer` with `PNGBitmapCodec` (the production save path), against the editor preview as the app builds it (`ThumbnailImage` proxy + `EditorProxy.displayScale` + `render`). A redaction-only control matches exactly | This is the live symptom on 400×500: "differs from the editor preview from row 251"; "the arrow at row 450 has 0 ink pixels delivered, 700 in the preview"; "the label drawn at row 30 repeats in rows 256–300 (198 ink pixels)" |
| `EditedOutputDefectTests.d23DownscaledPreviewDrawsMarksNoLargerThanTheSavedOutput(scale: 1, 2)` | D23 | It mirrors `EditorWindow.refresh()`: `EditorProxy.displaySize`/`displayScale` plus `render` over a uniform proxy, against the full-size whole render | The label and arrow are oversized: at 1× the label spans preview pixels (0,1)–(11,16) while the saved output covers only (0,1)–(6,9). The cause is the stroke and glyph cells floored at 2 px and the arrow head at 8 px. **The Solid redaction check passes**: at these integer downscales the preview redaction equals the block cover of the saved redaction, which is the Phase 2 "concealment wins" contract. The redaction part of D23 may only appear at non-integer proxy ratios |
| `DocumentRendererTests.d18FractionalCropKeepsTheRedactionOnTheContentItCovers` | D18 | `render` with crop | It replaces `fractionalCropAndRedactionSnapOutwardAfterCropAndScale`, which locked the sliver. Canary pixels under the redaction: "an original pixel under the Solid redaction shows at the crop edge"; the output is `##a.` rather than `.##.` |
| `DocumentRendererTests.d18TwoTimesCropKeepsTheRedactionOnItsContent` | D18 | `render` with a 2× crop | It replaces `twoTimesCropSnapsOutwardThenRedactsInTheCroppedOutput`, which locked the same unsnapped-origin shift. Here it over-covers an unselected row (no leak), so it will break when D18 is fixed |
| `EditedOutputDefectTests.d6LabelKeepsEveryTypedCharacter` | D6 | `render` with a label; each typed character must add ink | "typing '.' / '$' / '-' / '%' … adds nothing" (5 steps), and "lowercase v is drawn as uppercase V" |
| `EditedOutputParityTests.d21PartlyTransparentPixelsSurviveDoneWithoutDarkening` | D21 | `.done` through `CaptureCommandLayer` with `PNGBitmapCodec` | "RGBA(64,16,8,128) is delivered as RGBA(32,8,4,128)" |

**Evidence (x86_64 only):**
- `scripts/ci.sh`: green. 297 tests in 47 suites passed with 45 known issues, and the unsigned app build succeeded.
- `scripts/ci.sh --defects` lists d1 ×2, d6, d18 ×2, d21, d22 and d23 as red, and none as green.

**Notes for the fix tickets:**
- 52 or 65 should drop the D1 wrappers.
- 60 drops both D18 wrappers.
- 66 drops D6 and the label/arrow part of D23, and 68 drops the rest of D23.
- 67 drops D21.

### 2026-09-24: coordinator, resolved

Merged into `main`. At `ce152d4`, `scripts/ci.sh` is green (320 tests in 52 suites, 101 known issues), and `ci.sh --defects` lists this ticket's tests as red. x86_64 only.
