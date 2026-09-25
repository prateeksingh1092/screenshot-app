# 46: Red tests: scrolling capture round trip

**What to build:** Tests drive `ScrollingCaptureSession.ingest` the way a real scroll does: a synthetic page is sliced into viewport frames with steady, mid-step and flick steps, uniform bands and repeating content, and the stitched image must equal the page (D3). A 5K Retina frame sequence must not stop on an encoded-byte budget before the pixel cap (D20). The test image factory's repeating frame honours its period.

**Blocked by:** 43

**Phase:** 0

**Status:** resolved (tested on `main` at `ce152d4`)

- [x] A round-trip test through `ingest` covers steady and mid-step scrolls, uniform bands and repeating content. Each result equals the page exactly.
- [x] A flick on periodic content either equals the page or is reported as ambiguous. A result that is silently short or wrong fails.
- [x] The loops from branch `diagnose/red-loops` are ported without the `[DEBUG-d3h]` probes.
- [x] `repeatedScrollingFrame(period:)` uses its period.
- [x] D20: a 5,120-px-wide 2× frame sequence reaches the pixel cap without a budget stop.
- [x] The old `stitch(expectedStep:)` scenario tests, which skip the offset search, are not restored.
- [x] The red tests are marked as known defects.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: implementer, report

Claude Opus 5.5, Claude Code, medium effort. Branch `ticket/46-red-tests-scrolling-round-trip`. No product code changed.

**Seam.** Every test drives `ScrollingCaptureSession.ingest` and then `finish()`, and decodes the delivered PNG. `Stitcher.stitch(expectedStep:)` is not used, and the old 22 scenarios are not restored.

**New `Stitcher/ScrollingRoundTripTests.swift`.**
- `SyntheticScrollPage` mirrors the live `--show-scroll` page: uniform background, a 320×180 block every 400 rows, and an 8×8 marker. Options add unique markers and per-row textured blocks.
- An oracle, `evidencedDeltas` / `isAmbiguous`, lists every step whose overlap is identical and holds at least one non-flat row. A step is ambiguous when the true delta has no evidence or another delta has as much.
- `ScrollRoundTrip` reports produced vs expected rows, the first wrong row, whether a rejection was reported, and the ambiguous steps.

**Tests and red numbers.** Shown with `FRISKET_SHOW_DEFECTS=1`; they match the handoff's live and diagnosis numbers.

| Test | Defect | Red result |
|---|---|---|
| `d3SteadyScrollReproducesThePageExactly` (offsets 0…600 by 150, viewport 530) | D3 | 1121 of 1130 rows; first wrong row 542 |
| `d3MidStepSamplesReproduceThePageExactly` (0, 90, 150, …, 600) | D3 | 1066 of 1130; first wrong row 90 |
| `d3FlickOnAPeriodicPageIsExactOrReported` (0, 440) | D3 | 465 of 970; first wrong row 40; no rejection reported. The 440 overlap is flat, and only the wrong 40 has evidence. |
| `d3PeriodicContentIsNeverSilentlyMisaligned` (`repeatedScrollingFrame` period 48, steps of 80) | D3 | 464 of 560 rows; not reported |
| `d3RandomScrollsRoundTripExactly(seed: 1…8)` | D3 | All 8 red. Seed 7 has no ambiguous step, so exactness is required there: 1570 of 1750, first wrong row 55. The others, e.g. seed 4 (1358 of 1734, first wrong row 12), deliver wrong rows without reporting. |
| `ambiguityOracleSeparatesEvidencedStepsFromPeriodicOnes` | none | Green; a control for the oracle |

**New `Stitcher/ScrollingBudgetTests.swift`.**
- `d20FiveKRetinaScrollReachesThePixelCapWithoutABudgetStop` uses 5,120 × 2,880 frames with 2,560-row steps, with v1's encoded ceiling and memory budget. Rows are runs of 2–16 same-coloured pixels, which compress like screen content, and each row is unique.
- Red: the capture stopped with `encodedCeiling` at 8,000 of 15,680 rows after 4 viewports.
- The pixel cap is lowered to six viewports so the run stays short once the defect is fixed; the comment explains why this is still D20.
- Takes about 9 s in a debug build.

**Helper.** `TestImageFactory.repeatedScrollingFrame(period:)` now repeats every `period` rows, and `period` is required. Its ten existing callers, none of which wanted periodic content, now call `scrollingFrame`, which produces the same bytes as before, so they stay green.

**Evidence (x86_64 only).**
- `scripts/ci.sh`: green; 299 tests in 47 suites with 21 known issues, and the unsigned build succeeded.
- `scripts/ci.sh --defects` lists d3 (5 tests), d20 and d22 as red.

**Left open.**
- D20's second half is not covered at this seam: the coordinator refuses a whole capture whose final PNG exceeds 128 MB (`CaptureLifecycleCoordinator`).
- After the D20 fix, the O(n²) preview rebuild will dominate this test's run time, until ticket 72 makes the preview incremental.

### 2026-09-24: coordinator, resolved

Merged into `main`. At `ce152d4`, `scripts/ci.sh` is green (320 tests in 52 suites, 101 known issues), and `ci.sh --defects` lists this ticket's tests as red. x86_64 only.
