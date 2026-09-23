Model: Grok 4.7 High.

Core interface: `ScrollingCaptureSession` holds one manual scrolling capture. A `ScrollingFrameFeed` stand-in supplies viewports. There is no Accessibility permission, synthetic scroll, event tap, or global monitor. The pending original is LZFSE strips plus the previous viewport; each frame is released after it is copied. `ScrollingPreviewSurface` receives the live preview. Done returns a PNG from `captureScrolling`; Cancel drops the reservation. Thumbnail, Copy, and History then use the existing seam-1 commands.

Budgets come from the stitcher trial. The pixel cap is 294,912,000 (5,120 × 57,600), the capture ticket 34 completed at a peak physical footprint of 1,270,796,288 bytes. The memory budget is 2,000,000,000 bytes, the ticket 05 gate. A command also stops when retained strip bytes plus the next frame would exceed its reserved pending allowance. The app reserves 128 MB inside the 256 MB global pending budget and refuses a new scrolling capture when that budget cannot reserve the allowance. A pixel or memory stop keeps the section that fit and shows `ScrollingCaptureNotice.message`.

Peak memory, from `sh scripts/scrolling-memory-run.sh` in a fresh release process, using `TASK_VM_INFO.ledger_phys_footprint_peak` with no baseline subtracted: eight synthetic 1,920×1,080 frames at a 360-row step, PNG 180,578 bytes, peak 221,888,512 bytes, under 2,000,000,000. The live Activity Monitor figure stays manual.

Tests on x86_64 macOS 26.7 (25G229); arm64 not executed. Xcode 26.5 (17F42).

- `sh scripts/test-core.sh`: 107 tests in 17 suites passed; 4 opt-in skipped (stitcher memory, Vision probe, recorded sequences, this session memory).
- `sh scripts/scrolling-memory-run.sh`: 1 passed.
- Unsigned `xcodebuild` with `CODE_SIGNING_ALLOWED=NO`, `-resolvePackageDependencies`, and `-clonedSourcePackagesDirPath .build/SourcePackages`: BUILD SUCCEEDED.

Manual for Prateek, in `docs/manual-checks/35-scrolling-capture.md`: run `--show-scroll` only; select that page; scroll by hand; check the live preview, Done, Cancel, Copy, History, and the stop message; record the Activity Monitor peak. No real content. Stopped before review.
