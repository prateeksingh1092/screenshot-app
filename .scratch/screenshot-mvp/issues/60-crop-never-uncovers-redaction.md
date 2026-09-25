# 60: Crop never uncovers redacted pixels

**What to build:** A crop at fractional coordinates keeps every Solid redaction aligned with the content it covers, and no original pixel under a redaction shows at the crop edge (D18, story 96).

**Blocked by:** 44

**Phase:** 1

**Status:** resolved (tested on `main` at `22213c5`; live rows wait for an approved install)

- [x] The D18 test passes without the known-defect mark.
- [x] Canary tests at 1× and 2× with a fractional crop and scale pass for the clipboard, the saved file, History, the dragged file and the Thumbnail.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: implementer, report

Claude Opus 5.5 (1M context), Claude Code, high effort. Branch `ticket/60-crop-never-uncovers-redaction`.

**Cause.** `DocumentRenderer` cut the crop at whole output pixels (its origin snapped down), but it translated every mark by the crop's unsnapped, fractional origin. After a crop at x = 1.25, a redaction therefore landed 0.25 pt (0.25 × scale px) away from the content it covered, and snapping outward from that shifted position could leave an original pixel visible at the edge (D18).

**Fix (`Sources/FrisketCore/DocumentRenderer.swift`).** A new `cropOrigin` computes the crop's snapped top-left in output pixels, the same pixel `croppedRows` and `PNGBitmapCodec` start at. `paint` receives it as whole pixels. Every mark's geometry is now "scale and snap in uncropped output pixels, then subtract the whole-pixel origin": redactions, Blur/Magnify boxes, rectangles, arrows and labels. So a crop only removes pixels; every mark covers the same content it covers without the crop. `render` and both `forEachStrip` paths share this, so the editor preview, the strip save path and the whole render stay consistent. Annotations and effects in a fractionally cropped document can move by up to one output pixel compared with before; they now sit where they appear in the uncropped image.

**Tests:**
- `d18FractionalCropKeepsTheRedactionOnTheContentItCovers` and `d18TwoTimesCropKeepsTheRedactionOnItsContent`: wrappers removed. Red before the fix (the canary `a` showed; the 2× case over-covered row 0), green after.
- New core property test `fractionalCropEqualsCroppingTheUncroppedRender` (scale 1× and 2× × crop fraction 0.25, 0.5 and 0.75): rendering with the crop equals the uncropped render's snapped crop window. Red in all 6 cases on the old renderer.
- `EditorRedactionCommandsTests.cropKeepsRedactionsCompleteOnEveryOutput` gains fractional crops at 1× (10.5, 8.25, 17.75 × 13.5) and 2× (10.25, 8.25, 17.75 × 13.5), with hand-computed coverage. Its check is now exact: uncovered pixels must keep the background, so a shifted redaction fails as well as a leaking one. It runs through `.done` with `PNGBitmapCodec` and checks the History image, the pending revision, the Thumbnail image, the cached History thumbnail, the clipboard, the saved export and the dragged file. Before the fix the fractional cases leaked 8 (1×) and 9 (2×) canary pixels on every output. The existing whole-point cases still pass under the stricter check.
- No existing test locked the old behaviour beyond the two tests ticket 44 had already replaced.

**Evidence (x86_64 only):** `scripts/ci.sh` prints `ci: green` (321 tests in 52 suites, 98 known issues, unsigned app build included). `scripts/ci.sh --defects` no longer lists either D18 test as red.

**Left open (live):** a fractional crop made in the real editor (crop at a non-integer proxy position, then redact at the crop edge) should deliver no original pixel under the redaction on copy, save, drag, History and the Thumbnail. The package tests reach the render and delivery seams, not the editor's crop gesture.


### 2026-09-24: coordinator, integrated

Merged with tickets 60 and 63 (batch 1). `ci.sh` on `main` `22213c5` is green: 326 tests, 67 known issues. The live-matrix rows wait until Prateek approves installing a new build (docs/app-build.md).
