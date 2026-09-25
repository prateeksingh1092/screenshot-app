<!-- Provenance: Cursor Claude Opus 5.5 High subagent f16cf29f-b342-4a51-ae52-f28e4c0e15d8, round 1, 2026-09-22. Final response saved by the facilitator. -->

## Test architect: round 1

### Findings

**QA-1: Decision 23 names test areas but no seam, so tests would drift toward Snapzy's coupled style**
- Target: decision 23 (with 19)
- Attack: Snapzy's history, retention and clipboard tests run against shared singletons, wall-clock `Date()`, and the real general pasteboard. Ported as-is, they would test internals and overwrite Prateek's clipboard during local runs.
- Severity: blocker
- Evidence: `SnapzyTests/Services/History/CaptureHistoryRetentionServiceTests.swift:24,36,77`; `SnapzyTests/Services/Clipboard/ClipboardHelperTests.swift:60`; `.cursor/skills/matt-pocock/engineering/to-spec/SKILL.md:15`.
- Amendment: Make decision 19's command layer the single capture-lifecycle seam. Tests issue commands (capture, dismiss, open editor, redact, Done, Copy, Save, drag, launch recovery) against injected ports: `Clock`, app-owned `FileStore` (real temp dir), `PixelSource` (fixtures), `Pasteboard`, `DragHandoff`, `TextRecognizer`, and real GRDB in a temp dir. Tests observe only public queries and port recordings. Lifecycle, retention, forced-quit recovery and OCR-on-rendered-result all go through it. Two justified exceptions, as deep pure functions: renderer (document to bitmap) and stitcher (frames to image). Three seams total, rationale recorded in the spec.
- Changes an accepted product decision (1-12): no

**QA-2: Forced-quit recovery needs named commit points plus a few real kills**
- Target: decision 23 (with 16, 18)
- Attack: Real kills alone land at random moments and aren't repeatable. Fault injection over fakes alone can't show rename atomicity, durability (`fsync`), or SQLite WAL recovery.
- Severity: major
- Evidence: kill points in `docs/research/2026-09-22-snapzy-history-adaptation.md:52-57`; otherwise inference.
- Amendment: A closed list of named commit points (e.g. `pngWritten`, `rowInserted`, `thumbnailWritten`, `evictionRowDeleted`, `evictionFileDeleted`). Tier 1 (in process): inject a fault per point, discard the module instance, rebuild over the same directory, run recovery, assert invariants; run recovery twice (idempotence). Tier 2: a small package helper executable halts at a chosen point and `SIGKILL`s itself; the parent checks recovery. At least one Tier 2 case per point. A test fails if a point exists in code without a matching test.
- Changes an accepted product decision (1-12): no

**QA-3: Opaque-redaction checks must cover edge pixels and every output path**
- Target: decision 23 (with the solid redaction rule in 5, and 17)
- Attack: Fractional or 2x rectangles antialias, blending original pixels at edges. Color-space conversion (Display P3 to sRGB) can shift the fill. Checking only the renderer misses leaks via clipboard, drag files, history PNG and thumbnails.
- Severity: major
- Evidence: Snapzy's redaction tests build blur annotations, not solid fills (`AnnotateBackgroundRedactionTests.swift:131-135`); otherwise inference.
- Amendment: Snap redaction rectangles outward to the device-pixel grid and draw without antialiasing. "Canary" fixtures: source pixels under the redaction use unique colors that appear nowhere else. Through the command seam, decode every output (pasteboard, saved file, history PNG, drag file) in a fixed sRGB space; assert every covered pixel exactly equals the fill and no canary color appears anywhere. Cover 1x, 2x and fractional-point rectangles. Thumbnails must equal a downscale of the flattened image, not the original.
- Changes an accepted product decision (1-12): no

**QA-4: Use Swift Testing so tests run without Xcode**
- Target: decision 14
- Attack: XCTest is missing from the installed CLT, and every Snapzy test imports it (156 XCTest files, 0 Swift Testing). Ported verbatim, they break the "core builds and tests without Xcode" promise.
- Severity: major
- Evidence: `.scratch/evaluation/clt-probe/XCTestProbe.log:1`. A read-only listing shows `/Library/Developer/CommandLineTools/Library/Developer/Frameworks/Testing.framework` present; not run.
- Amendment: All package tests use Swift Testing. Before the spec is final, a probe ticket runs `swift test` with one `@Test` under CLT and records output. Performance timing (22) and anything needing an app host or UI automation is marked Xcode-only, or timed with `ContinuousClock` in a custom harness.
- Changes an accepted product decision (1-12): no

**QA-5: The arm64 slice can't be verified here**
- Target: decision 15
- Attack: "Universal from day one" implies both slices work; on this Intel Mac arm64 can only be compiled and inspected (`lipo -info`), never run. Snapzy's CI uses the `macos-15` label, believed to be Apple Silicon, so its history doesn't prove Intel either.
- Severity: major
- Evidence: `.scratch/evaluation/Snapzy/.github/workflows/ci.yml:15`; runner architecture from memory, not fetched: [GitHub runner images](https://github.com/actions/runner-images).
- Amendment: Every verification report states "Tests passed on Intel x86_64, macOS 26.7 build X, toolchain Y, commit Z. arm64: built and linked, not executed." A local `verify` script records this and fails on unexpected skips (no CI to enforce it). Alternative (partly reverses 15): x86_64 only until an Apple Silicon machine exists.
- Changes an accepted product decision (1-12): no

**QA-6: Vision makes stitcher and OCR tests OS-dependent; Snapzy's stitcher fixtures are missing**
- Target: decision 23 (with 13)
- Attack: Snapzy's stitcher calls a Vision image-registration request, so results can change with OS updates. One upstream test accepts either "appended" or "alignment failed" (passes regardless). The fixture README lists PNGs and a `Scroll/` directory that contains only the README. Snapzy's CI skips OCR tests.
- Severity: major
- Evidence: `Snapzy/Services/Capture/ScrollingCapture/ScrollingCaptureStitcher.swift:1667`; `ScrollingCaptureStitcherTests.swift:177-191`; `SnapzyTests/Fixtures/README.md:23-28`; `ci.yml:45`.
- Amendment:
  - Synthetic stitcher tests: generated frames (port `repeatedScrollingFrame`) with byte-exact expectations; record whether Vision was used.
  - Recorded stitcher sequences: a few real scroll sequences captured once (no personal content, provenance documented), including sticky headers and fixed footers; assert properties (height within tolerance, no duplicated bands via a unique marker column).
  - OCR at the seam: fake `TextRecognizer` checks it received the rendered revision and stale results are dropped.
  - Real Vision: a small tagged local-only set, pairing positive (canary text recognized when unredacted) with negative (absent once redacted), recording the OS build.
- Changes an accepted product decision (1-12): no

**QA-7: Manual runs need recorded evidence and fixed test scenes**
- Target: decision 23 (manual checklist)
- Attack: "Try capture on two displays" isn't repeatable or auditable; decision 21's local re-signing can silently reset Screen Recording.
- Severity: major
- Evidence: inference.
- Amendment: Each run records date, `sw_vers`, commit, `lipo` and `codesign -dv` (architectures, code hash), display layout (`system_profiler SPDisplaysDataType`), permission state. Uses a bundled test-pattern window at known coordinates; a script checks output dimensions and marker pixels. Required cases: Screen Recording not asked / denied / granted / revoked while running / after re-sign; mixed 1x and 2x displays; a display at negative coordinates; display disconnected mid-selection. No personal pixels in run records (decision 25).
- Changes an accepted product decision (1-12): no

**QA-8: Port Snapzy test scenarios, not its test code**
- Target: decision 13
- Attack: Some upstream tests assert the opposite of our rules; some rely on private reflection.
- Severity: minor
- Evidence: `AreaSelectionMultiMonitorReconciliationTests.swift:33-47,60` (`Mirror` on a singleton); `AnnotationSessionStoreTests` protects persisted originals (history research, line 44).
- Amendment:
  - Port with the code: deterministic stitcher tests (`ScrollingCaptureStitcherTests.swift:298-483`), `TestImageFactory`, frozen-snapshot and render-equivalence tests (`AnnotateRenderSnapshotTests.swift:36-140`), `ArrowGeometryTests`, `ScreenCaptureAreaCropTests`, `AreaSelectionCaptureCoordinateSpaceTests`.
  - Rewrite against the seam: retention, history store, database migration, multi-monitor scenarios.
  - Drop or invert: `ClipboardHelperTests`, `AnnotateBackgroundRedactionTests`, `AnnotationSessionStoreTests`, and outcome-agnostic stitcher tests.
- Changes an accepted product decision (1-12): no

### Keep
- Decision 16: memory-only originals remove a whole class of leftover files recovery tests would otherwise hunt.
- Decision 19: one command layer is exactly the single high seam to-spec asks for.
- Decision 18: "the just-committed item is never evicted" is sharp and testable.

### Questions only Prateek can answer
- Do you have an external display, ideally 1x, for the multi-display checklist? If not, those cases can't run.
- Is "arm64 built but never run" acceptable for v1, or Intel-only until Apple Silicon testing is possible?
