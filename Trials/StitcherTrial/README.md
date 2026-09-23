# Stitcher trial (tickets 04 and 05)

An isolated evaluation package; Frisket's root package does not depend on it.
Ticket 05 implementation is ready for separate review. Porting is a
**recommendation, not an accepted decision**. Prateek's choice and the
coordinator's outside-sandbox Vision result remain pending.

## Ticket 05: strip storage

The matcher compares the incoming frame only with the previous **accepted**
frame; rejected intermediates do not replace that reference. Copied new rows
are packed into 256-row strips (only the final strip can be shorter), compressed
losslessly with Foundation's LZFSE API. Compression failure retains the copied
raw strip. No strip retains a frame raster. The previous raster is replaced
on acceptance; caller CGImages are not retained. There is no disk I/O or
temporary-image path in the stitcher or synthetic generators. SwiftPM caches
and redirected textual evidence logs are build artifacts, not capture storage.

`forEachStrip` delivers lossless images in output order for incremental
rendering/encoding. `mergedImage()` returns an immutable Core Graphics image
whose data provider reads compressed strips on demand, with one decoded strip
cached. Output snapshots remain valid after append, restart, and stitcher
release. A consumer requesting all image bytes still allocates a full bitmap;
the provider avoids an additional stitcher-owned full bitmap. No PNG encoder
or app integration is included in this trial.

Static header/footer detection now checks exact row boundaries instead of
rounding up to its sampling stride. Once movement establishes static bands,
they are excluded from output, preserving the extracted stitcher's existing
content-only behavior. The 31-row-header/27-row-footer fixture verifies every
content byte across two appends. This is synthetic coverage, not a recorded
real-screen sequence.

## Ticket 05: reproduce

From the repository root, normal fast suite (full-size and Vision probes skip):

```sh
sh Trials/StitcherTrial/scripts/test.sh
```

Full-size opt-in run (release; compiles first with the test disabled, then runs
only this test in a new process):

```sh
sh Trials/StitcherTrial/scripts/memory-run.sh
```

Repeatable Vision probe, including the exact command for the coordinator to run
outside Codex's sandbox on this Mac:

```sh
sh /Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-05/Trials/StitcherTrial/scripts/vision-probe.sh
```

All scripts pin `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, use
in-trial build/cache/config/security directories, disable SwiftPM's nested
sandbox and keychain access, and use Swift Testing (`--disable-xctest`). No
network, package installation, signing, screen capture, or clipboard is used.

## Ticket 05: measured memory

2026-09-23 UTC; x86_64, macOS 26.7 **25G229**, Xcode 26.5 **17F42**, Swift
6.3.2. **arm64 not executed.**

- Generate 79 viewports (5120×1440, 720-row steps) from a deterministic,
  nonperiodic synthetic document of coloured 8×16 cells, entirely in memory.
  Each viewport and its autorelease pool are released after submission.
- Output is exactly **5120×57,600**, **225 strips**, **1,179,648,000 RGBA bytes**.
  Check every strip and every byte of the full image against generated source
  pixels. No full reference canvas, truncation, or downscaling.
- Measure `task_info(mach_task_self_, TASK_VM_INFO)` →
  `ledger_phys_footprint_peak`, the kernel-maintained lifetime high-water mark
  in bytes. Validate return code, returned field availability, and nonzero peak.
  This is physical footprint, not RSS, and includes the test runner, fixture
  generation, alignment, compressed storage, full output-byte materialization,
  and validation. It cannot miss spikes between samples. Build processes are
  separate; no baseline is subtracted.
- **Before output-provider change:** 3,664,924,672 bytes, 48.894 seconds; all
  pixels correct, budget assertion failed.
- **After:** **1,289,433,088 bytes** (1.289 GB / 1.201 GiB), **35.617 seconds**
  measured inside the test; test runner reports 35.698 seconds. The strict
  assertion is `< 2,000,000,000` bytes, not 2 GiB. **Passed.**
- Vision estimates used: **0** in the sandboxed full-size run. Alignment used
  the pixel matcher. This is a fixture-specific memory result, not proof that
  arbitrary/incompressible captures or concurrent pending captures fit the
  budget, and does not establish the production pixel cap.

## Ticket 05: Vision result and TDD evidence

The opt-in probe requests real `VNTranslationalImageRegistrationRequest`
alignment of a synthetic 320×400 textured pair displaced by 80 pixels. It
requires horizontal shift <2 pixels, vertical shift within 2 pixels of 80,
then requires the stitcher to report `usedVisionEstimate == true`, append 80
rows, and produce height 480. A passing pixel fallback cannot pass the probe.

Inside Codex's sandbox: **failed**, `NSOSStatusErrorDomain -6662`,
`Failed to create CVPixelBuffer Width = 320, Height = 400, Format = '420f'`.
The `kern.hv_vmm_present` sysctl diagnostic also appeared. This locates the
failure at Vision pixel-buffer allocation; it does not prove a sandbox or GPU
root cause. No CPU/GPU policy was changed. Outside-sandbox result is pending
coordinator execution; no successful Vision alignment is claimed.

All behavior changes used the pre-approved seam 3 and red → green, without a
refactor or review step:

1. `initialFrameStreamsFixedSizeStripsWithoutChangingPixels`: missing API
   (red); compressed 256/256/88-row output is byte-exact (green).
2. `doesNotRetainCallerFrameAfterCopyingRows`: caller image remained retained
   by the initial-image cache (red); independently owned output releases it
   (green).
3. `stickyHeaderAndFooterAreExcludedAtExactRowBoundaries`: output was 558 rows
   instead of 560 and lost two rows (red); exact boundary detection preserves
   all 560 rows (green).
4. `fullSizeCaptureFitsPhysicalFootprintBudget`: full output exceeded the
   physical-footprint limit (red above); strip-backed provider and bounded
   autorelease scopes pass the identical test (green above).
5. Additional regression checks verify successive accepted-frame alignment
   beyond the initial overlap, fixed strip boundaries across partial appends,
   input lifetime, immutable delivered strips, and image snapshot lifetime.
   Existing behavior checks that already passed needed no production changes.

The final suite counts and review handoff are in
[05-implementer.md](../../.scratch/screenshot-mvp/reports/05-implementer.md).
The alternative cost comparison is a
[recommendation](../../.scratch/screenshot-mvp/reports/05-port-or-fresh.md).
Local raw red/green/probe logs are in `.build/evidence/05-*.log` (ignored).

## Ticket 04 baseline (historical)

The following records the extraction before ticket 05's changes. Its outstanding
strip-storage and memory work is addressed above; the Vision limitation remains.

## Source and attribution

Read-only reference: `/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.scratch/evaluation/Snapzy/`.
Upstream: https://github.com/duongductrong/Snapzy
Commit: `837fc73d9b55dfde203e9d14aeb8c8fae4f0add7`.

The source, factory, and 22 existing tests come from the paths recorded in
[`docs/ported-files.json`](../../docs/ported-files.json). The original files
have descriptive banners rather than per-file BSD text. Those banners remain
verbatim, preceded by the full upstream BSD-3-Clause licence. `LICENSE` is a
byte-for-byte copy of upstream's licence; the ledger also records original
source SHA-256 hashes. The clone is never written to.

## Reproduce

Run this block from either this directory (trial) or the repository root
(Frisket core). All caches are local to that working directory. No dependency
resolution, downloads, signing, capture, or clipboard are needed.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build --disable-sandbox --disable-keychain \
  --cache-path .build/cache --scratch-path .build \
  --config-path .build/config --security-path .build/security
swift test --disable-sandbox --disable-keychain --disable-xctest \
  --cache-path .build/cache --scratch-path .build \
  --config-path .build/config --security-path .build/security
```

For focused runs append `--filter testStart_initializesCorrectly` or
`--filter testAppend_settled`. Run repository checkers from the repository root:

```sh
for check in dependencies imports identity provenance; do
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/python3 \
    Checks/check_repository.py --root . --check "$check" || exit
done
for fixture in Checks/Fixtures/*.json; do
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/python3 \
    Checks/check_repository.py --fixture "$fixture" || exit
done
```

## Dependencies and changes

- Production imports: Foundation, CoreGraphics, Vision. No extra direct runtime
  framework or third-party dependency. Replace upstream's unused `AppKit`
  import with `CoreGraphics`; no app coordinator or app host is required.
- Tests additionally use toolchain-provided `Testing`; the manifest uses
  `PackageDescription`. The image factory is unchanged apart from attribution.
- Convert the existing XCTest suite to a Swift Testing struct with `@Test`,
  `#expect`, `#require`, and `Issue.record`; add explicit Foundation for `Data`
  and change the tested module to `StitcherTrial`. Preserve all 22 scenarios
  and their assertions, including the byte-exact final-strip test.
- Add a conservative fallback for settled partial steps when Vision returns no
  estimate. A unique, byte-exact overlap supplies the short-step prior and
  exempts only that exact matched delta from the known-step contradiction check.
  It rejects identical frames and ambiguous exact overlaps, retains the
  existing 12-row minimum, and requires at least 96 overlapping rows. Existing
  scoring and ambiguity checks still apply. It does not accept noisy overlaps
  or enable partial steps for frames not explicitly marked settled.
- Extend repository static-check inventory explicitly to this package's
  manifest, licence, source, test, and resource inputs. Apply existing identity
  and provenance rules; do not ignore the trial. Respect the selected Xcode
  toolchain during the root manifest check. See `docs/core-package.md` for scope.

## Red → green evidence

The seams were pre-approved in decisions 23/41 and the specification: stitcher
input frames/output image and repository-check CLI. No private state is tested.
These are existing upstream scenarios, converted before any implementation was
copied, rather than speculative new tests written in bulk.

1. Converted all 22 tests and copied the factory. With only an empty module,
   the focused initialization run failed because `ScrollingCaptureStitcher`
   was missing. After extraction and the import change, it passed (1 test).
2. Three new on-disk static fixtures failed with `got []` before adding trial
   discovery. They now detect identity leakage, forbidden AppKit imports, and
   missing provenance in both source and test files.
3. The settled-step pair initially passed 1/2. The final 12-pixel strip was
   rejected at offset 172. The same test failed alone, then also failed when
   minimized to an initial frame plus a single 12-pixel scroll.
4. Temporary diagnostics showed Vision returning `NSOSStatusErrorDomain -6662`
   while allocating `420f` CVPixelBuffers (220×330 and 220×236). A temporary
   CPU-only request still failed. Neither diagnostic code nor the deprecated
   CPU-only setting remains. This establishes a failure on this restricted
   host, not its cause or Vision behavior outside this environment.
5. Restored the original test unchanged. The byte-exact fallback made both
   settled tests pass (2/2), including rejection of the oversized jump.

Local raw logs are in `.build/evidence/` (ignored generated output). The final
run counts and timings are recorded in the
[implementer draft](../../.scratch/screenshot-mvp/reports/04-implementer.md).
Implementation and verification: Codex (GPT-6 Astra, high); no complementary
agent, review, or commit performed.

## Cost comparison handoff

Compilation required package scaffolding and one import substitution; test
execution additionally required Swift Testing conversion and the exact-overlap
fallback. Attribution and static inventory changes are trial integration costs.
No refactor was performed. Elapsed implementation time is in the draft report.

The measured host is x86_64, macOS 26.7 build 25G229, Xcode 26.5 (17F42), Swift
6.3.2. **arm64 not executed.** Tests use synthetic images, but the matcher still
attempts real local Vision registration. Successful Vision-assisted alignment
has not been verified here; passing via the fallback must not be reported as
such. The SDK remains linked, and its internal frameworks are not additional
direct dependencies of this package.

Retained upstream coverage has limits: the shifted-content test allows alignment
failure, and the height-limit/render-suppression tests largely assert non-nil
updates. There are no sticky-header/footer fixtures in the supplied 22-test
suite. Ticket 05 still needs those checks, fixed-size strip storage, a complete
5120×57,600 run and physical-footprint measurement below 2 GB, and a comparison
against fresh implementation. Current slices retain whole frame rasters and
merged output allocates a full bitmap. No memory-budget or adoption claim is
made by this extraction.
