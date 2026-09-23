# Ticket 04 implementer draft

Implemented; stopped before review.

Created `Trials/StitcherTrial/` containing `Package.swift`, `LICENSE`, `README.md`,
`Sources/StitcherTrial/ScrollingCaptureStitcher.swift`, and
`Tests/StitcherTrialTests/{ScrollingCaptureStitcherTests,TestImageFactory}.swift`;
three `Checks/Fixtures/trial-*-inventory.json` fixtures; and this report. Updated
checker/fixture runner, core documentation, notices, and provenance ledger.
Frisket's manifest remains unchanged.

Reference commit: `837fc73d9b55dfde203e9d14aeb8c8fae4f0add7`.
Clone cleanliness, source hashes, licence bytes, and all 22 test names verified.

Ran `swift build` and `swift test --disable-xctest` from each package directory,
both with:

```sh
--disable-sandbox --disable-keychain --cache-path .build/cache \
--scratch-path .build --config-path .build/config --security-path .build/security
```

Environment: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`,
`CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-cache`,
`SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/module-cache`.

Both builds passed. Trial: **22/22 tests**, 2.414s. Root: **3/3 test functions,
21 cases** (4 repository checks, 16 fixtures, 1 toolchain check), 5.966s.
`git diff --check` passed. Host: **x86_64, macOS 26.7 (25G229)**;
Xcode 26.5 (17F42), Swift 6.3.2. **arm64 not executed.**

Cost: measured **10m 50s**, 03:53:57–04:04:47 UTC on
2026-09-23; excludes initial instruction reading and review. Changes: Swift
Testing conversion before extraction, AppKit→CoreGraphics import, attribution,
explicit checker inventory, and a unique byte-exact settled-partial-overlap
fallback after an inherited test failed. No refactor. No extra direct runtime
dependencies beyond Foundation/CoreGraphics/Vision; tests additionally use Testing.

Open issues: Vision pixel-buffer allocation returned **-6662** even CPU-only;
Vision-assisted success remains unverified. Ticket 05 still owns strip storage,
sticky-band coverage, the 5120×57,600/2 GB run, and port-versus-fresh decision.
See the trial README for red→green evidence and coverage limits.

No review, staging, commit, or ticket status/checkbox edits.
