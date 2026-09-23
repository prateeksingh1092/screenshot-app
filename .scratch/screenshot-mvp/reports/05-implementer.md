# Ticket 05 implementer draft

Implementation and verification by Codex (GPT-6 Astra, high). **Stopped before
review.** No review invocation, delegation, staging, commit, ticket Status or
checkbox edits, or decision recording. No complementary model was used.

## What changed

Inside `Trials/StitcherTrial/`:

- Replace frame-retaining slices with copied, losslessly LZFSE-compressed
  256-row strips. Only the last strip may be partial, and later appends fill
  it before opening another. Compression failure retains a copied raw strip.
- Remove the retained initial raster and cached caller image. Alignment still
  compares only the incoming frame and previous accepted frame; a rejected
  intermediate never replaces the reference. Release caller images after
  copying and replace the previous raster after each accepted append.
- Add `forEachStrip` and a CGImage data provider backed by immutable compressed
  strip snapshots with one decoded strip cached. This avoids the inherited
  full-array → full-Data output copies. Bound strip autorelease lifetimes.
- Correct static header/footer detection at individual-row boundaries; an odd
  31-row header and 27-row footer previously removed two content rows. Preserve
  the extracted content-only output semantics (detected static bands excluded).
- Add five deterministic strip/lifetime/sticky tests, an opt-in full-size
  memory test, and an opt-in real Vision probe. Add reproducible shell commands
  and update the README with exact evidence and limitations.

Reports: this draft and [05-port-or-fresh.md](05-port-or-fresh.md). Existing
BSD headers, original banners, licence bytes and provenance ledger remain
unchanged. Frisket's manifest is unchanged. No writes to the reference clone.
There are no disk/file/temporary-image APIs in the stitcher or the generators;
all capture pixels stay in memory. SwiftPM caches and textual evidence logs are
build artifacts. No network, installs, sudo, xcode-select, signing, keychain,
real screen capture, clipboard, or prohibited memory paths were used.

## Tests and commands

Host verified live: **x86_64**, **macOS 26.7 (25G229)**, **Xcode 26.5 (17F42)**,
**Swift 6.3.2**. **arm64 not executed.** Swift Testing throughout.

From the repository root:

```sh
# Full normal trial suite.
sh Trials/StitcherTrial/scripts/test.sh

# Opt-in full-size release run, built separately before measurement.
sh Trials/StitcherTrial/scripts/memory-run.sh

# Vision probe; exact absolute command works inside or outside the sandbox.
sh /Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-05/Trials/StitcherTrial/scripts/vision-probe.sh
```

Scripts set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`,
`CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-cache`, and
`SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/module-cache` after changing into the
trial. They use `--disable-sandbox --disable-keychain --disable-xctest
--cache-path .build/cache --scratch-path .build --config-path .build/config
--security-path .build/security`. The memory command uses `-c release`, then
`--skip-build` in a fresh test process with `FRISKET_MEMORY_RUN=1`; the Vision
command uses `FRISKET_VISION_PROBE=1`. Neither probe runs by default.

The root suite was run with:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift test --disable-sandbox --disable-keychain --disable-xctest \
  --cache-path .build/cache --scratch-path .build \
  --config-path .build/config --security-path .build/security
```

| Run | Result |
| --- | --- |
| Final trial normal suite | **27 passed, 2 opt-in skipped**, 29 discovered in 4 suites, 2.335s; all 22 inherited scenarios retained |
| Full-size opt-in test | **1 passed**, 35.698s runner time; measured work 35.617403416s |
| Vision opt-in probe | **1 failed** at Vision CVPixelBuffer allocation; see below |
| Final root suite | **3 test functions, 21 cases passed**, 1.375s: 4 repository checks, 16 fixture cases, 1 toolchain case |
| Static and shell checks | Root dependency/import/identity/provenance checks passed; `git diff --check` and `sh -n` for all 3 scripts passed |

Normal debug compilation and the release memory build both succeeded. Focused
runs used `--filter` with the test names below or `StripStorageTests` and
`testAppend_settled`; final suites ran once after implementation.

## Red → green evidence at approved seam 3

1. Strip delivery test failed to compile because `forEachStrip` did not exist.
   Added compressed strip storage/delivery; 600 source rows became exactly
   `[256, 256, 88]`, preserving every byte.
2. Caller-frame lifetime test failed because the start cache retained the input
   CGImage. Independent output storage released it; the test passed.
3. Sticky-header/footer test expected 560 rows, received 558, and failed exact
   byte comparison. Per-row boundary detection made it pass; settled-step
   regression tests also passed.
4. The full-size capture produced correct pixels but peaked at
   **3,664,924,672 bytes**, failing `< 2,000,000,000` in **48.893702778s**.
   The strip-backed provider and bounded autorelease scopes passed the unchanged
   full-size test at the peak below. No refactor step or separate review ran.
5. Additional regression tests verify the already-working previous-accepted-frame
   behavior across five appends beyond any overlap with the initial frame,
   byte-exact coalesced strip output, release of every caller frame, and immutable
   strip/full-image snapshots after append, restart and stitcher release.

Raw local logs: `Trials/StitcherTrial/.build/evidence/05-01-{red,green}.log`,
`05-02-{red,green}.log`, `05-03-{red,green}.log`, `05-04-red.log`,
`05-04-focused.log`, `05-04-green.log`, `05-final-trial.log`,
`05-vision-probe.log`; root `.build/evidence/05-final-core.log`.
These generated logs are ignored; durable results are recorded here and in
[the trial README](../../../Trials/StitcherTrial/README.md).

## Physical-footprint run

- Synthetic 5120×57,600 document, generated as 79 individual 5120×1440 frames
  at 720-row scroll steps. Deterministic nonperiodic coloured 8×16 cells; no
  full reference canvas and no file-backed input. All frames were accepted.
- Output: exactly **225 strips / 57,600 rows / 5120 columns**. Materialize the
  full CGImage's bytes as a consumer would and verify its dimensions and byte
  length; compare all **1,179,648,000 bytes** and every streamed strip with
  freshly generated reference rows. No truncation or downscaling.
- Method: `task_info(mach_task_self_, TASK_VM_INFO)` and
  `ledger_phys_footprint_peak`, with return-code/field-availability/nonzero
  checks. The kernel high-water ledger covers spikes, includes runner overhead
  and the full output-byte materialization/validation, and does not subtract a
  baseline. It is physical footprint rather than resident-set size. Build
  processes run before the measured test process.
- **Peak: 1,289,433,088 bytes (1.289 GB / 1.201 GiB).**
- **Elapsed: 35.617403416 seconds**, measured with `ContinuousClock` from before
  fixture generation through verification and the footprint query; test runner
  completion 35.698 seconds.
- Limit: strict **2,000,000,000 bytes**, passed. **0 Vision estimates** used in
  this sandboxed run. Result is for this fixture; arbitrary entropy, successful
  outside-sandbox Vision allocations and concurrent captures remain unmeasured.
  Production memory admission, encoding and pixel-cap decisions remain later work.

## Vision probe and coordinator handoff

The probe performs real translational registration of two synthetic textured
320×400 frames, then requires the actual stitcher to use a Vision estimate and
append the expected 80 rows. Both direct displacement and final height are
asserted. Pixel fallback alone cannot pass it.

Inside the sandbox: **failed**, `NSOSStatusErrorDomain -6662`,
`Failed to create CVPixelBuffer Width = 320, Height = 400, Format = '420f'`.
The `kern.hv_vmm_present` sysctl diagnostic also appeared. This reproduces ticket
04 and identifies the failing allocation, but does not prove the sandbox or a
GPU policy is the cause. No GPU/CPU setting was changed.

**Outside-sandbox result: pending coordinator execution** of the exact command
above. No outside result was supplied during this implementation session, and
no Vision-assisted success is claimed. The documented failure is evidence,
not a passing Vision test.

## Cost and acceptance handoff

Ticket 05's measured implementation/verification checkpoint: **13m 40s**,
**2026-09-23 04:11:58–04:25:38 UTC**, excluding initial required reading,
this final draft/handoff, future external runs and review. Ticket 04 recorded
10m 50s, so combined measured checkpoints total **24m 30s**. This is agent
wall time, not a calibrated human engineering estimate.

Recommendation: **continue with the adapted port**, subject to review and the
outside-sandbox probe. The [comparison report](05-port-or-fresh.md) separates
measured port effort from an explicitly unmeasured fresh-build estimate and
requires the same frozen tests for either alternative. No second implementation
was built or benchmarked.

The technical strip-storage, synthetic memory and deterministic-test work is
ready for the coordinator's review snapshot. The Vision external result and
**Prateek's port-or-fresh decision remain pending**. In particular, the ticket's
last acceptance criterion is owned by Prateek/coordinator and is intentionally
not fulfilled by inventing or recording a decision. Ticket status/checkboxes
and the decisions file remain untouched, as instructed.
