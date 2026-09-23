# Scrolling capture stitcher

Decision 48 adopts the ticket 05 port at seam 3. `Stitcher.stitch(_:)` consumes
one `Sequence<ScrollingCaptureFrame>` and returns `StitchedCapture`: a Core
Graphics image plus alignment evidence in input order. The core imports only
Foundation, CoreGraphics and Vision here; it has no AppKit, SwiftUI, capture,
clipboard, filesystem, or temporary-image path.

Each frame carries its image and optional `expectedVerticalStep` in pixels.
It must be positive and smaller than the viewport height. Manual scrolling normally omits that hint. `isSettled` permits an independently
verified short final step. The sequence describes overlapping, same-sized
viewports moving downward. Detected static headers and footers are excluded
from the output once movement establishes their exact row boundaries. A lone
viewport, or one repeated without movement, retains its full height.

Empty input throws `emptySequence`; inconsistent dimensions or invalid hints throw
`invalidFrame`; raster/output construction failure throws `imageUnavailable`.

Alignment reports distinguish initial, appended, unchanged and rejected frames,
with appended rows, confidence, pixel/total scores and successful Vision use.
A rejected intermediate never replaces the last accepted frame. Callers must
inspect these results before treating the image as a complete Scrolling capture;
an unalignable sequence can return only its accepted prefix. No rejected frame
is silently claimed as stitched. Initial appended rows describe initialization,
not final content height after static bands have been removed.

Use a lazy sequence for large captures. The function advances it inside an
autorelease pool and owns only the previous accepted raster, compressed 256-row
strips, and small alignment records. Passing an array retains the caller's
frames. The returned image has an independent, immutable strip-backed provider
with one decoded-strip cache; asking for all bytes allocates a full output
bitmap. No global state or storage is mutated. Vision is local registration,
not OCR. Failure to obtain a Vision estimate leaves the pixel matcher active.

The inherited matcher and its regression suite remain internal. Its preview,
mutable start/append and strip iteration methods are not exposed to app callers.
The public sequence tests and full-size run exercise the pure product interface.
The live session is a bounded exception described below.
The existing 22 scenarios and five strip/lifetime/sticky tests retain the
trial's regression coverage, including its deliberately conservative cases.

## Live scrolling session exception (ticket 35 fix pass)

`ScrollingCaptureSession` is the sole product-side owner allowed to use the
internal matcher's incremental methods. The coordinator serializes access to
one session. App adapters supply `ScrollingFrameFeed` events; they never receive
the matcher. This exception uses the documentation option authorized by the
fix-35 brief; it does not replace the pure sequence contract for completed inputs.

`Stitcher.stitch(_:)` synchronously consumes a finite `Sequence` and returns only
at its end. The live feed awaits ScreenCaptureKit and human Done/Cancel choices,
updates a preview between frames, and checks retained-byte and pixel budgets
before accepting more content. The existing pure interface cannot await that
feed, emit intermediate previews, or stop at a requested output height. Buffering
all viewports until Done violates prompt frame release and removes the live
preview. Replaying all prior viewports for each preview retains capture-sized
input history and repeats earlier matching. Feeding the tall result plus the
next viewport instead violates the equal-viewport-dimensions contract and loses
the previous-viewport matching state. A blocking synchronous bridge would also
need extra control and preview side effects, so would not preserve purity.

The session therefore keeps one incremental matcher, compressed output strips
and the previous accepted raster. It uses the same matching algorithm as the
pure function and does not replay previous input frames. Tests compare each live
preview's dimensions and the final decoded pixels with the pure result and an
independent synthetic document. Existing frame-release, cap, memory-stop and
opt-in memory tests exercise the constraints requiring this exception.

An alignment rejection is terminal for a live session: ingest emits
`rejectedAlignment` with disposition, scores, appended-row count, confidence and
Vision-use evidence; the accepted prefix is released and `finish()` returns nil.
The command returns `captureFailed(.rejectedAlignment(evidence))`, releases its
reservation and creates no thumbnail. Diagnostics retain only the closed
`rejectedAlignment` code. True no-movement still returns `unchanged`. The pure
function continues to return its accepted prefix plus all alignment records,
so its callers must still inspect those records.

## Reproduce

From the worktree root:

```sh
sh scripts/test-core.sh --filter StitcherTests
sh scripts/stitcher-memory-run.sh
sh scripts/stitcher-vision-probe.sh
```

Scripts pin Xcode 26.5 and use the in-worktree cache/config/security paths from
[core-package.md](core-package.md). Memory and Vision probes are opt-in and
skip in the normal full suite (`sh scripts/test-core.sh`). The coordinator
runs the Vision probe outside the Codex sandbox; it requires a successful
Vision estimate, so a pixel fallback cannot pass. No screen or clipboard is used.

The memory run constructs 79 synthetic 5120×1440 viewports at 720-row steps,
requires exactly 5120×57,600, and compares all 1,179,648,000 output bytes with
independently generated document pixels in 256-row chunks. It uses the same
kernel `TASK_VM_INFO.ledger_phys_footprint_peak` measurement and strict decimal
`< 2,000,000,000` assertion as ticket 05, including full byte materialization.
The release test compiles in a separate process before measurement. No baseline
is subtracted. This synthetic result is not a production pixel cap or a bound
for arbitrary entropy, concurrent Pending captures, or downstream encoding.

## Trial retirement and attribution

`Trials/StitcherTrial/` was removed in ticket 34: its evaluation is complete,
and a second package would duplicate implementation, tests and provenance.
Core now owns all execution. The [historical trial record](stitcher-trial-history.md)
and ticket 04/05 reports preserve the earlier findings and red/green evidence.
The unchanged upstream licence is at [licenses/Snapzy-LICENSE](licenses/Snapzy-LICENSE).
Headers, original hashes, adapted hashes and change notes are registered in
[ported-files.json](ported-files.json). Snapzy is listed as a product component
in [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md).

## Recorded sequence acceptance

The [fixture guide](../Tests/Fixtures/ScrollingCapture/README.md) documents the
PNG/JSON format, provenance, height tolerance and unique-band oracle. The
synthetic sticky sequence passes through that loader in the normal suite. The
real-recording test is opt-in and fails if no cases exist. **Real recordings
remain pending Prateek authorization; ticket 34 does not satisfy that criterion.**

## Ticket 34 red → green evidence

The spec already approved seam 3; the user required red → green with no refactor
step. Focused test/typecheck runs produced these cycles (local ignored logs in
`.build/evidence/34-*`):

- Sequence image test: missing `Stitcher`/frame types → exact 560-row image and
  alignment evidence through the new public interface.
- Settled final step: missing settled input → all 532 rows, including the final
  12, preserved byte-for-byte.
- Rejected intermediate: missing disposition/scoring evidence → explicit
  rejection, unchanged accepted reference, then exact accepted output.
- Invalid input: missing typed invalid-frame failure → invalid hints (including
  integer extremes) and inconsistent dimensions rejected; empty input also checked.
- Recording-format test: missing loader → file-loaded synthetic sticky sequence
  exact, with negative duplicate-band and wrong-height controls.
- Memory-only checker: forbidden CoreGraphics/Vision in stitcher → narrowly
  allowed there, with disk writes still rejected. Existing diagnostics check
  caught the inherited strip-decode assertion → typed failure replaces it.
- Provenance hash fixture: altered hash incorrectly accepted → changed bytes
  rejected independently of a retained valid licence header.

The unchanged inherited scenarios, manual-scroll lazy input lifetime test and
five strip/lifetime tests needed no further matcher changes. No review,
staging, commit, ticket status edit or checkbox edit was performed.

## Ticket 34 verification (2026-09-23 UTC)

- Host: x86_64, macOS 26.7 (25G229), Xcode 26.5 (17F42), Swift 6.3.2.
  **arm64 not executed.**
- `sh scripts/test-core.sh`: 51 discovered test functions, **48 passed, 3
  opt-in tests skipped**, 7 suites, 3.980 seconds. Parameterized checks include
  all six repository checks and 22 checker fixtures. Identity and provenance
  pass. Skips are memory, Vision and real recordings.
- `sh scripts/stitcher-memory-run.sh`: separate release process, **1 passed**,
  79 frames, exact 5120×57,600, all 1,179,648,000 bytes checked in 225 chunks.
  Kernel lifetime peak physical footprint **1,270,796,288 bytes** (1.271 GB),
  below 2,000,000,000; measured interval 40.639 seconds. **0 Vision estimates**.
- The public synthetic, manual-scroll and recording-format tests also report
  **0 Vision estimates** in this sandbox. The core retains Vision registration;
  these results exercise its pixel fallback. Ticket 34 did not execute the
  opt-in Vision probe here. The coordinator must run
  `sh scripts/stitcher-vision-probe.sh` outside the sandbox and attach that new
  result; ticket 05's outside-sandbox success is historical evidence only.
- **Real recorded sequences remain pending.** The synthetic folder validates
  the format and property oracle; it does not satisfy real-scroll acceptance.

Raw local logs: `.build/evidence/34-full-suite.log`, `34-memory.log`,
`34-ported-tests.log`, `34-manual-sequence.log`, `34-static-green.log`, and
`34-01` through `34-07` red/green evidence where applicable. No reviewed
snapshot or commit is claimed.
