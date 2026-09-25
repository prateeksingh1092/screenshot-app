Model: Grok 4.7 High.

Core interface: `ScrollingCaptureSession` holds one manual scrolling capture. A `ScrollingFrameFeed` stand-in supplies viewports. There is no Accessibility permission, synthetic scroll, event tap, or global monitor. The pending original is LZFSE strips plus the previous viewport; each frame is released after it is copied. `ScrollingPreviewSurface` receives the live preview. Done returns a PNG from `captureScrolling`; Cancel drops the reservation. Thumbnail, Copy, and History then use the existing seam-1 commands.

Budgets come from the stitcher trial. The pixel cap is 294,912,000 (5,120 × 57,600), the capture ticket 34 completed at a peak physical footprint of 1,270,796,288 bytes. The memory budget is 2,000,000,000 bytes, the ticket 05 gate. A command also stops when retained strip bytes plus the next frame would exceed its reserved pending allowance. The app reserves 128 MB inside the 256 MB global pending budget and refuses a new scrolling capture when that budget cannot reserve the allowance. A pixel or memory stop keeps the section that fit and shows `ScrollingCaptureNotice.message`.

Peak memory, from `sh scripts/scrolling-memory-run.sh` in a fresh release process, using `TASK_VM_INFO.ledger_phys_footprint_peak` with no baseline subtracted: eight synthetic 1,920×1,080 frames at a 360-row step, PNG 180,578 bytes, peak 221,888,512 bytes, under 2,000,000,000. The live Activity Monitor figure stays manual.

Tests on x86_64 macOS 26.7 (25G229); arm64 not executed. Xcode 26.5 (17F42).

- `sh scripts/test-core.sh`: 107 tests in 17 suites passed; 4 opt-in skipped (stitcher memory, Vision probe, recorded sequences, this session memory).
- `sh scripts/scrolling-memory-run.sh`: 1 passed.
- Unsigned `xcodebuild` with `CODE_SIGNING_ALLOWED=NO`, `-resolvePackageDependencies`, and `-clonedSourcePackagesDirPath .build/SourcePackages`: BUILD SUCCEEDED.

Manual for Prateek, in `docs/manual-checks/35-scrolling-capture.md`: run `--show-scroll` only; select that page; scroll by hand; check the live preview, Done, Cancel, Copy, History, and the stop message; record the Activity Monitor peak. No real content. Stopped before review.

## Fix pass

2026-09-23. Codex fix-35 session, following implementation workflow step 6 and
the local TDD skill at the existing command, adapter and stitcher seams.

All four review findings were validated. Three required runtime corrections;
the pure-interface finding uses the brief's explicit documentation alternative:

- **Alignment rejection:** `.ignoredAlignmentFailed` now emits typed rejection
  evidence instead of `.unchanged`. The session releases its accepted prefix,
  remains terminal after rejection and cannot finish an incomplete image. The
  command returns `captureFailed(.rejectedAlignment(evidence))`, frees the
  reservation and creates no pending thumbnail. Disposition, scores, appended
  rows, confidence and Vision use survive in the outcome. Diagnostics record
  only the closed rejection code. Actual no-movement remains unchanged.
- **Stitcher interface:** `docs/stitcher.md` now documents the live-session
  exception. The pure function synchronously consumes a sequence to completion;
  it cannot await the live feed, publish per-frame previews or enforce the
  session's incremental height/retained-byte stops. Buffering or replaying every
  viewport conflicts with prompt release and bounded retention. The session
  therefore retains its private incremental matcher. App callers still use the
  session/command interfaces. The pure sequence contract remains unchanged.
- **Permission reservation:** scrolling bytes and capture ID are reserved before
  awaiting permission, matching area/full-screen policy. Denial releases both.
  Competing commands cannot exceed the global allowance or reuse the ID during
  that suspension.
- **In-flight Cancel:** the panel cancellation action is checked immediately
  after `captureRegion`, including both error paths. A returning viewport cannot
  trigger a limit thumbnail after Cancel.

### Regression evidence

Each runtime correction was made after its behavioral regression failed:

- Alignment red returned `.pending` for an unrelated second viewport followed
  by Done. Green returns the typed rejection and no image, with budget released.
- Reservation red allowed all three competing capture modes through the
  permission suspension, both for exhausted budget and duplicate ID. Green
  rejects all six combinations. Four denied/revoked/relaunch permission states
  additionally verify complete reservation release and no frame request.
- Cancel red retained a limit thumbnail on successful capture return and lost
  cancellation on an error. Green returns `.captureFailed(.cancelled)` in both
  cases, with no pending image. Continuation gates control these races without
  timing guesses or real capture.

The interface resolution is documentation-only, so there is no claimed failing
runtime test for that finding. Added compatibility checks verify live previews
before Done, unchanged frames, byte-exact agreement with both the pure stitcher
and an independent synthetic document, equal rejection evidence, and rejection
remaining terminal. Existing frame-release and budget regressions also pass.

### Verification

Host rechecked: x86_64, macOS 26.7 (25G229), Xcode 26.5 (17F42). arm64 was not run.

- Focused command/adapter/stitcher run: 42 tests passed in 4 suites.
- Final full `swift test` via `sh scripts/test-core.sh`: 114 discovered test functions;
  **110 passed, 4 opt-in skipped**, 17 suites, 8.613 seconds. Includes all eight
  repository static checks and their fixture checks. Skips: full-size stitcher
  memory, Vision probe, real recordings, and scrolling-session memory (run
  separately below). Pure synthetic tests reported zero Vision estimates.

Local raw logs are under `.build/evidence/35-fix-*`: alignment, reservation and
cancel red/green logs, focused log, full-suite log and memory log. No broad
review was relaunched, no ticket Status or checkbox was edited, and no real
screen/clipboard capture was performed. No findings remain open under the
brief's permitted documentation option. Real recorded sequence acceptance and
outside-sandbox Vision validation retain their existing limitations.


### Memory fixture correction

The first fix-pass release memory run failed: `finish()` correctly returned nil.
Adding per-frame acceptance/height assertions located the rejection at offset
360, the second 1,920×1,080 viewport. The old repeated-band fixture is ambiguous
without a scroll-distance hint. Its test discarded every ingest result and only
required a nonempty PNG. **The earlier 221,888,512-byte measurement above does
not establish a complete eight-frame stitch**; it permitted an accepted prefix.
The initial failure and stricter red are retained in `35-fix-memory.log` and
`35-fix-memory-fixture-red.log`.

The success fixture now uses nonperiodic synthetic document cells (the same
construction as the full-size stitcher fixture), with the same eight viewports,
1,920×1,080 size and 360-row step. It requires every preview to advance to its
expected height, an exact 1,920×3,600 PNG, and equality of all 27,648,000 decoded
bytes against the independently generated complete document. The old ambiguous
pair remains in the normal suite: it must either be rejected with no finished
image or append the full 360 rows; an unchanged prefix fails. No matcher tuning
or weakened rejection policy was used to obtain a memory pass.

The strengthened debug memory run passed at 263,204,864 bytes; it is a diagnostic
run, not the separate release measurement. Its log is
`35-fix-memory-fixture-green.log`. The final full-suite rerun above includes the
new ambiguous-input regression; raw log: `35-fix-full-suite-final.log`.

Final `sh scripts/scrolling-memory-run.sh`: **1 passed** in the fresh release
process after a separate build, 1.507 seconds. Eight accepted viewports,
1,920×3,600 complete output, all 27,648,000 decoded bytes verified, PNG 395,826
bytes. Kernel lifetime peak physical footprint **262,017,024 bytes (0.262 GB)**,
with no baseline subtraction, below 2,000,000,000. This supersedes the earlier
incomplete-fixture result; it remains synthetic evidence rather than a live
Activity Monitor or real-recording measurement. Final log:
`.build/evidence/35-fix-memory-final.log`.
