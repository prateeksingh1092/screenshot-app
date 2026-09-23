# Stitcher extraction trial (ticket 04)

This scratch Swift package evaluates the stitcher separately from Frisket.
The root package has no dependency on it. Adoption and strip storage remain
ticket 05 work and require that ticket's evidence and decision.

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
