# Frisket remediation, re-architecture, and simplification plan

Status: **proposed, not executed** (2026-09-24). Owner: Prateek. Repo HEAD: `73be4ce` (Frisket 0.1.0, build 8).
This plan follows a full-session evaluation. It sequences the work and does not change any code.

---

## 0. Context

**Why this plan exists.** Frisket passes its automated suite: 286 Swift tests in 44 suites, a clean build with zero project warnings, and 79% line coverage. The live use tests still found several defects that change delivered pixels or make a capture mode unusable. None of them was caught, because:
- the tests exercise tiny fixtures and fakes;
- the 3,383-line app layer has no tests;
- none of the 30 manual checks was ever executed.

A same-harness comparison with the installed CleanShot X 5.0.1 showed that the failing areas are ones where Frisket hand-rolled something that a native API or a more conventional design gets right by default.

**Evidence sources (all from this session):**
1. **Static review:** four parallel reviewers covered the data lifecycle, capture and stitcher, the editor and renderer, and the app shell and process.
2. **Live beta:** first a detached run (18:50–19:05), then a main-session run (19:50–20:15) using a synthetic-pattern harness. Notes are in `.scratch/visual-pass/beta/0-summary.md` and files 1–4, with PNG evidence in `evidence/` (gitignored).
3. **Architecture audit:** three explorers covered native-API choices, left-over/erratic/scalability issues and modularity, and concurrency/tooling/test strategy.
4. **CleanShot X 5.0.1 hands-on benchmark:** the same pattern tools and tests as Frisket (§1.3).
5. **Web and GitHub research** on native and adjacent APIs and open-source screenshot tools (§1.5).

**Intended outcome:**
- Every delivered image is identical to what the user saw.
- Every capture mode works on this Mac's display pair (Retina 2× plus an external 1×).
- The fragile hand-rolled subsystems are replaced by native APIs, or reduced to the minimum the product decisions actually require.
- The codebase is smaller, has one build graph, has CI, and has tests that would have caught every live bug.

**Plan at a glance:**

| Phase | Purpose | Size | Gate |
|---|---|---|---|
| −1 | Record decisions; Prateek signs DA-2, DA-7, DA-10, DA-11; spec deltas and tickets | XS | Decisions recorded |
| 0 | One build graph (step 1), local CI, a red test per defect, live harness in-repo | S–M | Every D-test red for the right reason |
| 1 | Hotfixes: D1 interim, D2, D3 stopgap, D4, D5, D7, D8, O10, D10–D14, D18, D19, D25 | S | ◆ A: stopgap stitch measured → O4 scope |
| 2 | Native CoreGraphics/CoreText/ImageIO renderer, preview parity, editor action bar, `NSUndoManager` | M–L | ◆ B: memory at 5120×32,768 |
| 3 | Scrolling rework: Vision-assisted best-score matcher, retry UX, incremental preview, 32,768-px cap | M–L | Round trip exact; matches CleanShot on the harness page |
| 4 | Coordinator state enum, one outcome presenter, geometry helper, adapters product, app-layer tests | M | Presenters tested |
| 5 | Shortcut detection instead of takeover, History simplification, slim checks, dead code, docs, process, polish | S–M | Signed DAs |
| 6 | Acceptance: CI, live matrix, remaining manual checks, performance | S–M | Ticket 40 closed |

---

## 1. Evidence summary

### 1.1 Baseline (measured)

| Item | Result |
|---|---|
| `scripts/test-core.sh` | 286 tests / 44 suites pass (about 16 s) |
| Unsigned Development build (Xcode 26.5) | Succeeds; 0 project warnings |
| Line coverage | 79% overall; core mostly 93–100%. 0%: SelectionOverlay, WindowSelectionOverlay, WindowScreenCapturePlatform, VisionTextRecognizer, SelectionSizeBadge, ScreenCaptureContent |
| App target (`Frisket/*.swift`, 3,383 lines) | No test target |
| Python tool tests / `check_repository.py` | Pass. There is **no network rule**; ticket 40's "no network entitlement" item means little while `ENABLE_APP_SANDBOX = NO` |
| Manual checks (`docs/manual-checks/*`) | 0 of 30 executed |
| Tickets | 40 of 41 "resolved"; 31 of those have pending manual criteria. Ticket 40 is in progress, and its worktree predates the stitcher rewrite |

### 1.2 Confirmed defects

"Live" means reproduced in the running app. "Probe" means reproduced with the real code in a standalone program. "Static" means code-verified only.

| ID | Defect | Sev | Proof | Root cause (file:line) | Class |
|---|---|---|---|---|---|
| D1 | Saved or copied edits differ from the preview. On a 400×500 image the arrow at row 450 is missing and the label repeats every 256 rows (731 ink pixels per band, 0 in the arrow band). The History file is byte-identical to that output | **Critical** | Live, Probe | `DocumentRenderer.swift:305-314`: arrow and text ignore `rowShift`. Blur halo is only 1 row (`:71`); magnify takes its origin from the strip (`:226`) | Hand-rolled strip renderer |
| D2 | Window capture (⌘⇧5) selects the mouse cursor. ScreenCaptureKit lists "Cursor" (layer 2147483630) with an empty bundle ID. Click goes through, Tab doesn't move, and Return shows a misleading "Capture unavailable… smaller area" | **High** | Live | `WindowSelection.swift:36` rejects only `nil` bundle IDs (`SCRunningApplication.bundleIdentifier` is non-optional, so `""` passes). Floating windows are allowed on purpose (`:31-32`), and there is no level ceiling | Filter gap |
| D3 | Scrolling capture silently corrupts content: 36 rows lost across 2 seams, blocks start 15 and 34 rows early, and a marker is squashed from 8 rows to 3. A fast flick silently truncates the result below the selected height (416 < 530). **CleanShot's stitch of the same page and steps is exact** | **High** | Live | `ScrollingCaptureStitcher.swift`: first-zero `searchDelta` (`:390`), 24-column integer-mean `rowDistance` (`:398-413`), header/footer trimming up to 1/3 of the viewport (`:353-362`). 250 ms sampling (`ManualScrollingCapture.swift:59-63`) | Hand-rolled matcher (rewritten in `3d43926`) |
| D4 | Clicks inside the area-selection hole and the window cut go through to the app underneath. The overlay then loses keyboard focus, and only a click on the veil recovers | **High** | Live | `SelectionOverlay.swift:153-154` and `WindowSelectionOverlay.swift:151-152`: alpha-0 holes, and `ignoresMouseEvents` never set | AppKit default not overridden |
| D5 | Editor Done/Copy/Save/Close exist only in the toolbar's `>>` overflow at the default width, and their key equivalents die when overflowed | **High** | Live | `EditorWindow.swift:229-238`, `:529-532` | Toolbar design |
| D6 | Text labels drop characters: `v2.1 $4.99 -10%` → `V21 499 10` | Med-High | Live | `AnnotationFont.swift:9` (A–Z, 0–9 and space, uppercase only) | Hand-rolled 5×7 font |
| D7 | A cancelled drag commits to History and leaves a 744 B edited PNG in `staging/drag/`, which survives Delete | Medium | Live | `CaptureLifecycleCoordinator.swift:424` commits before the outcome; `DragStagingLifetime.swift:54-58` cleans up only after both events. The staged bytes are never read | Custom staging lifetime |
| D8 | Copy Text on a textless image replaces the clipboard with an empty string and shows a modal "Copied 0 characters". **CleanShot leaves the clipboard untouched** | Medium | Live | `CaptureLifecycleCoordinator.swift:634-638`, `PasteboardAdapter.swift:40-43`, `CaptureSurfaces.swift:299-300` | Logic |
| D9 | Pending cards overlap instead of stacking (seen twice). **CleanShot uses fixed-size cards** | Medium | Live | `CaptureSurfaces.swift:497-503` steps by the newest card's height; heights vary (`ThumbnailPanel.swift:304-324`) | Layout |
| D10 | History Delete (key or button) has no confirmation or undo. It fails while the capture's card is open, showing "Delete failed. Try again.", which can't succeed | Medium | Live | `HistoryWindow.swift:148-150`; the core refuses deletes while the card is open | UX and logic |
| D11 | The scrolling panel eats Page Down and Space (it takes key on every preview). Regression from `73be4ce` | Medium | Live | `ManualScrollingCapture.swift:188-190` | Regression |
| D12 | ⌘⇧2 "focus latest thumbnail" moves only accessibility focus; keys go to the frontmost app | Medium | Live | `ThumbnailPanel.swift:228`, `:345` | Panel type |
| D13 | All 7 macOS screenshot shortcuts are off on this Mac, and Frisket's restore record (`systemScreenshotHotkeys.turnedOffByFrisket`) is empty, so Settings offers no Restore. Launch re-claims them every time, which is decision 55 as written. A user who uninstalls loses ⌘⇧3/4/5 | Med-High (design) | Live, Static | `FrisketApp.swift:171-186`; `SystemScreenshotHotkeyStore.swift:11`, `:24-31`, `:49-84` (private plist write, `notify_post` via `@_silgen_name`) | Decision 55 mechanism |
| D14 | Pointer on the top pixel row: no origin display, and the overlay is not key | Low-Med | Live | `ScreenCapturePlatform.swift:85`, `DisplaySelectionSession.swift:43-44` (half-open bounds) | Edge case |
| D15 | History and Settings open on the other display without focus. Settings' first focus lands in the auto-dismiss field | Low-Med | Live | Window restoration and focus | UX |
| D16 | Accessibility: a committed card is still announced as "Pending capture" with stale Edit and Delete actions, and its close action is a no-op. History rows speak their label three times. The card picture has no accessibility element | Low-Med | Live | `ThumbnailPanel.swift`, `HistoryWindow.swift` | a11y |
| D17 | Silent Save with `Frisket-<UUID>-rN.png` names; About shows raw Markdown and internal text; Copy/Delete Latest are enabled when there is nothing to copy or delete; ⌘⇧ vs ⇧⌘ order is inconsistent | Low | Live | various | Polish |
| D18 | A fractional crop shifts redactions and leaves a 1-px sliver of original pixels. A test locks the wrong behavior | Medium (privacy) | Probe | `DocumentRenderer.swift:92-93`; `DocumentRendererTests.swift:110-124` | Geometry |
| D19 | After "Try Again", History row actions fail until the next commit, because the writer stays closed | Medium | Static | `HistoryStore.swift:163-165` vs `:332`, `:353` | Logic |
| D20 | Scrolling encoded ceiling counts raw frames. At 5K 2× a capture stops after about 2 screens, and a final PNG over 128 MB refuses the whole capture | High on Retina/5K | Static | `ScrollingCaptureSession.swift:151`, `ScrollingCaptureStitcher.swift:150`, `CaptureLifecycleCoordinator.swift:603-608` | Budget model |
| D21 | Premultiplied bytes are written as a straight-alpha PNG, so edited window corners get dark fringes | Low-Med | Static | `StripPNGEncoder.swift:43-47`, `:190` | Hand-rolled encoder |
| D22 | C functions (`compression_stream_*`, `crc32`, `adler32`, `notify_post`) are called through `@_silgen_name`, with the Swift calling convention | High (UB risk) | Static | `StripPNGEncoder.swift:151-171`, `SystemScreenshotHotkeyStore.swift:4` | Import fence workaround |
| D23 | The downscaled editor preview draws redactions larger than the saved output (outward rounding), and floors stroke and glyph cells at 2 px | Medium | Static | `EditorWindow.swift:357-360`; `DocumentRenderer.swift:277`, `:315` | Preview path |
| D24 | Recovery and drag staging share `staging/` with no lock, and quota can double-count after a finalize crash | Low-Med | Static | `HistoryStore.swift:122`, `:141-148`, `:518-546` | Storage |
| D25 | Coordinator reentrancy: `.deleteHistory` and `copyRecognizedText` don't set `inProgress`, and quit stops at the first capture it cannot finalize | Low | Static | `CaptureLifecycleCoordinator.swift:166-170`, `:294-300`, `:621-646` | Concurrency |
| D27 | A fresh History store sometimes gets `.rootLocked` just after the previous owner closed the same root. It fails CI at random. Found 2026-09-24: 2 of 8 runs when History tests run beside tests that start child processes, 0 of 15 alone | Low (CI reliability) | Probe | `HistoryStore.swift` `HistoryRootLock.acquire` (flock on the root directory). Unverified hypothesis: a child process that another thread is starting briefly shares the closed owner's descriptor | Lock mechanism |

### 1.3 CleanShot X 5.0.1 benchmark (same harness, same display pair)

| Test | Frisket 73be4ce | CleanShot X | Takeaway for Frisket |
|---|---|---|---|
| Area capture pixel fidelity | Exact 320×180, exact sRGB, concealed clipboard | 321×181 (the end pixel is included); keeps the display ICC (sRGB conversion is optional); clipboard holds a file URL plus PNG, not concealed | Frisket is ahead on fidelity and privacy. Keep |
| Selection model | Persistent adjustable selection with a badge and keyboard nudges; the hole lets clicks through | Captures on mouse-up; no persistent hole | Keep adjustability, but make the hole hit-testable (D4) |
| Window capture | Targets the cursor, so unusable (D2) | Picks the real window; adds wallpaper padding and a shadow (2182×1342 for a 1920×1080 window) | Filter by window layer; optional shadow and background later |
| Scrolling capture, same page and steps | 36 rows lost; a flick truncates | **Exact** (blocks 400 apart, 90/90/8 rows). In-place frame, live side preview, Cancel/Done at the region, a "Please slow down…" warning | Rework the matcher; add speed feedback and in-place controls |
| Annotate, tall image | Arrow missing, label duplicated, glyphs dropped | Output identical to the preview; real font; Done and "Save as…" always visible; Copy, Share, Pin and Upload in a bottom bar; a "Drag Me" handle | Native rendering; always-visible exits |
| Redaction | Dedicated solid redaction, guaranteed opaque black (`--verify-redacted` passes under blur and magnify) | Filled rectangle in the chosen color, plus pixelate and redact tools; no locked black | **Frisket's differentiator. Keep** |
| OCR, text | Modal "Copied N characters" | Copies silently; a first-use tip explains it | Non-modal feedback |
| OCR, no text | Wipes the clipboard | Clipboard untouched | Fix (D8) |
| Thumbnail stack | Cards overlap | Fixed-size cards, evenly stacked; hover reveals Copy/Save, with corner Close/Pin/Annotate/Upload; tooltips show shortcuts. Corner buttons have **no accessibility labels** | Fixed-size cards; keep Frisket's better labels |
| History | 30-day/1 GB archive with a dedicated window and row actions; GRDB, sidecars, a ledger, fsync | **3-day restore buffer** in a top strip with type filters; Restore puts the capture back into a thumbnail card; stored as one folder per capture plus a list in preferences | See O5: simplify the model and reuse the card |
| After-capture behavior | Fixed lifecycle | A per-type action matrix: overlay, copy, save, upload, annotate, pin | A small action matrix is optional (Phase 5) |
| URL automation | None (decision 19) | URL API **off by default**, with a consent prompt | Keep none; if added later, copy the consent model |
| System shortcuts | Private plist rewrite at every launch | Binds ⇧⌘3/4/5 itself; users turn off the macOS shortcuts by hand in System Settings (community guidance; no official doc found) | Stop writing the plist; detect the collision read-only and deep-link to System Settings (DA-2) |

CleanShot state after the test: 12 synthetic-pattern captures were added to its media folder and expire under its 3-day retention. No settings were changed, the URL API prompt was declined, and it was quit (it had not been running).

### 1.4 Architecture and code health (audit)

**Layering:**
- The core has no AppKit, which is sound.
- But the fence leaks: hand-declared zlib/libcompression symbols, PNG encoding in the core (contradicting `docs/core-package.md:219`), and user-facing strings in the core.
- **Dual build graph (Medium):**
  - The app's synchronized folder compiles `Frisket/Adapters`, which is also compiled as the SwiftPM `FrisketAdapters` target used by tests.
  - `Sources/FrisketCore` is a separate Xcode static-library target (`pbxproj:26-27`) and also a SwiftPM target.
  - GRDB is pinned twice (both exact 7.11.1), and there are two `Package.resolved` files.
  - Tests exercise only the SwiftPM copies. The sources are identical, so drift risk is moderate.

**God objects:**
- **`CaptureLifecycleCoordinator`:** 16 dependencies and about 13 parallel sets or dictionaries keyed by capture ID. It is an implicit state machine, and its `.drag` path duplicates `deliver()`.
- **`CaptureSurfaces`:** the outcome→UI mapping is written 6 times, and they have drifted.
- **`HistoryStore`:** 895 lines covering storage, recovery, retention, thumbnails and the lock.
- **`EditorWindow`:** keeps its own undo stack instead of `NSUndoManager`.
- **`AppController`.**

**Erratic code:**
- Magic numbers: 256, 24, 250 ms, 2048, 480 (×4), and the Carbon masks.
- Mixed coordinate origins; the flip code is duplicated, and the display-ID lookup appears 5 times.
- `try?` swallowing, and force unwraps in `HistoryStore` (`:470`, `:564`, `:800`).
- Three notice mechanisms, including success shown as a modal.

**Left-over code:**
- Vision fields and a probe that can never pass.
- Snapzy-era fields in the stitcher; test-only public API.
- An empty `discardSelectionPreviews()`, and an empty `FrisketCore.swift`.
- Snapzy provenance checks while `ported-files.json` is empty.
- Diagnostics that are written and never read.
- Stale docs: `stitcher.md`, `core-package.md:243`, `cursor-workflow.md:51`, `SESSION-CHECKPOINT.md`, and the old ⌃⌥⌘ shortcuts in 9 manual checks.

**Scalability:**
- History window reload is O(n²).
- The scrolling preview rebuilds the full page each frame (O(n²), with about 1.2 GB transient near the cap).
- `SCShareableContent` is fetched on every sample.
- Full-image decodes defeat the strip design.
- Quota eviction costs about 4 checkpoints plus fsyncs per row.
- Heavy work happens on the main actor (editor re-render per edit, thumbnail decode, PNG encode).
- The coordinator actor serializes the Done re-encode and stitching.

**Concurrency:**
- There are 4 `@preconcurrency` ScreenCaptureKit imports and 2 unlocked `@unchecked Sendable` types.
- `@_silgen_name` is used 6 times (D22).
- Swift 6 language mode already implies complete checking.

**Tooling:**
- No CI and no hooks.
- `check_repository.py` (448 lines) parses Swift with regex and brace counting.
- A run-script phase runs on every build.
- `SDKROOT=macosx26.5` is pinned.
- Manual signing is hard-coded to team `9M43Q952NK`.
- The Xcode scheme has no test action.

**Tests that let the bugs through:**
- The strip test covers redactions only.
- There is no empty-bundle-ID window.
- The stitcher's 22 scenarios (518 lines) were deleted in `3d43926`, and `repeatedScrollingFrame` ignores `period`.
- The drag-cancel path is faked.
- There is no empty-OCR case.
- There are no app or UI tests.

**Process weight:**
- 179 of 516 tracked files are in `.scratch`: about 2 lines of process text per line of product code.
- On disk, `.scratch` is 949 MB and `.worktrees` is 2 GB.

### 1.5 Over-engineering and native-alternative assessment

Research sources are cited in Appendix B.

| # | Subsystem (today) | Cost today | Native or simpler alternative | Prevents | Verdict |
|---|---|---|---|---|---|
| O1 | CPU strip renderer (430 LOC), 5×7 bitmap font (58), strip PNG encoder with `@_silgen_name` zlib (200) | D1, D6, D18, D21, D22, D23 | Draw everything with CoreGraphics into a `CGContext` (per strip, `translateBy(0, -rowShift)`, or whole image under the O14 cap), labels with CoreText, and write PNG with `CGImageDestination`. Redaction stays a separate opaque, non-antialiased copy-blend pass. Snapzy, Capso and macshot all export this way. ImageIO has no row-streaming PNG API, which is why the cap in O14 matters | D1, D6, D21, D22; simplifies D18 and D23 | **Replace** (keep the redaction rules and golden tests) |
| O2 | Custom window picker | D2 | Keep it. Filter the way Capso and Snapzy do: reject an empty owning-app bundle ID, set a level ceiling below the Dock/pop-up levels (the cursor sits at 2147483630), a minimum size (e.g. ≥ 32 pt), and exclude the Dock bundle and own app. **Keep the deliberate floating-window support** (`WindowSelection.swift:31-32`; test `foreignFloatingWindowIsCapturedAheadOfOverlappingNormalWindow`). `SCContentSharingPicker` (macOS 14+) is an optional later path; it doesn't persist picks and still needs the Screen Recording grant | D2 | **Keep + fix** |
| O3 | Custom area overlay with a persistent hole | D4, D14 | Keep: it is needed for decisions 16, 33 and 36 (`screencapture -i` only writes to disk or the clipboard). The panels are already key-capable `.screenSaver` `NSPanel`s (`SelectionOverlay.swift:4-7`, `:33-37`). The only missing piece is `ignoresMouseEvents = false`, which is exactly Capso's design. A frozen-screenshot background is optional (macshot and Capso freeze; CleanShot offers it). If adopted, it must use the same exclusion filter and be discarded on cancel. Use a closed-interval display lookup | D4, D14 | **Keep + fix** |
| O4 | Hand-written row matcher, rewritten today | D3, D20, perf | Vision `VNTranslationalImageRegistrationRequest` as the primary delta, as in macshot, Capso and ScrollSnap (which moved to Vision from template matching). Verify it with a dense best-score pixel check (not first-zero). Detect sticky headers across frames. Reuse `SCShareableContent` between environment-generation changes instead of fetching it per sample; move to an `SCStream` (Snapzy: 30 fps) only if the sampling rate proves too low. Add an incremental preview, "slow down" feedback, and keep the accepted prefix on failure. Flat content breaks every mature stitcher (Snapzy #609, macshot #386, CleanShot 4.4), so design a retry UX rather than chase perfection. Restore the deleted scenario tests | D3, D20 | **Rework** |
| O5 | History: GRDB, sidecar JSON, ownership ledger, `F_FULLFSYNC`/`renamex_np`, flock, 11 commit points (895 LOC) | D19, D24, O(n²), eviction cost | Snapzy and Capso keep GRDB rows with file paths, age/count retention and a sweep at launch or daily. macshot keeps a JSON index plus folders. SQLite transactions are crash-durable at the default synchronous setting. So: atomic PNG writes plus GRDB defaults plus a launch sweep for orphans, with the sidecars, ledger and full-fsync chain removed | Mostly perf and complexity; no live bug | **Simplify (DA-4)** |
| O6 | Drag staging lifetime (file promise plus a fsynced staged copy that is never read) | D7 | The coordinator commits when it receives the promise-written event (`DragCopyEvents`), so authorization stays in the coordinator. The promise is written from memory. Staging is deleted. This is **mandatory**, because staging an unfinalized render to disk breaks CONTEXT.md's "Pending capture" definition (decisions 16 and 31) | D7 | **Replace** |
| O7 | Private `com.apple.symbolichotkeys` rewrite at every launch, plus `notify_post` via `@_silgen_name` | D13, D22 | No comparable tool writes that plist. Snapzy reads it and opens System Settings; KeyboardShortcuts only warns; Apple's documented path is manual (System Settings › Keyboard › Keyboard Shortcuts › Screenshots). Keep the ⌘⇧ defaults and Carbon registration, but detect collisions read-only (`SystemShortcutReader` already exists) and deep-link the user to System Settings. Restoring what Frisket turned off is an **opt-in** button: restoring automatically would take ⌘⇧3/4/5 back from Frisket | D13, part of D22 | **Replace (DA-2)** |
| O8 | `NSToolbar` with seven tools and trailing actions | D5 | A content-area action bar (Done and Copy always visible; Save and Drag next to them), or `visibilityPriority = .high` on the actions, plus main-menu responder actions for ⌘C/⌘S/Return | D5 | **Replace** |
| O9 | Three notice paths, including a modal `NSAlert` for success | D8, UX | One non-modal notice service that reuses the card status line and VoiceOver announcements; modals only for destructive choices | D8 (UX part) | **Replace** |
| O10 | Variable-height cards with custom stacking math | D9 | Fixed card size (image aspect-fit inside), cumulative layout | D9 | **Replace** |
| O11 | Custom undo stack | Risk | `NSUndoManager` | — | **Replace** |
| O12 | `check_repository.py` regex fence plus an every-build script phase | Fragility, false confidence | Run a slim check from `scripts/ci.sh` and a pre-push hook, not from the build. Enforce what the compiler can (SwiftPM target boundaries). **Port these invariants by name before deleting any rule:**<br>(1) `AuthorizedFinalization` is built only in the coordinator;<br>(2) no app writes outside finalization;<br>(3) storage never receives original pixels;<br>(4) the core does no disk I/O;<br>(5) no event taps or global monitors;<br>(6) new: no network APIs | — | **Slim + relocate** |
| O13 | Dual Xcode/SwiftPM compilation | Moderate drift | Step 1 (safe): replace the Xcode `FrisketCore` target with the SwiftPM product; one GRDB pin. Step 2 (Phase 4): expose `FrisketAdapters` as a product. This needs about 22 adapter files made `public` and conflicts with Phase 1 edits, so do it later | — | **Replace, in two steps** |
| O14 | Byte budgets (`CaptureBudgets.v1`: 256/128 MB encoded, 2 GB peak) and a 57,600-row scrolling cap | D20; the strip encoder exists only to serve it | One output-height cap of **32,768 px** (Snapzy's cap, and within CoreGraphics/ImageIO dimension limits). That makes a whole-image `CGContext` feasible (5120 × 32,768 × 4 ≈ 671 MB). Measure peak memory; encoded size becomes only a History-admission check (decision 27) | D20; enables O1 without a custom encoder | **Simplify (DA-6)** |
| O15 | Process artifacts (red team, 26 reviews, 41 tickets, 30 unexecuted manual checks) | Velocity; stale docs | CI plus automated equivalence tests plus one scripted live harness (`/tmp/frisket-beta` promoted to `Tools/LiveHarness`). None of the comparable open-source repos carry similar artefacts; macshot ships ordinary unit and fuzz tests | Future regressions | **Trim** |
| O16 | Capture API | — | Already native: `SCScreenshotManager.captureImage(contentFilter:configuration:)` with `sourceRect` (`ScreenCaptureContent.swift:17-22`). The macOS 26 `captureScreenshot(rect:)` API takes no content filter, so it would drop the exclusion list (decision 37) and the self-exclusion (`ScreenCapturePolicy.swift:32-34`) | — | **No change** |
| O17 | In-house diagnostics actor (in memory, never read) and an opt-in latency log | Dead weight | A few `os.Logger` calls with privacy annotations, plus `OSSignposter` for latency, satisfy decision 25 with no Frisket-written files. Or delete them outright | — | **Replace with os.Logger, or delete** |
| O18 | Hand-off to system Markup instead of an in-house editor | — | Rejected: there is no public API. Third-party code uses the private `com.apple.MarkupUI.Markup` sharing service, which is unverified on macOS 26 | — | **Keep own editor** |
| O19 | VisionKit Live Text (`ImageAnalysisOverlayView`) instead of Vision OCR | — | Rejected for Copy Text: its system copy doesn't mark the clipboard concealed or this-Mac-only (decision 36). It is optional later for in-editor text selection | — | **Keep Vision OCR** |
| O20 | `screencapture -i` as the capture backend | — | Rejected: it only writes to a file or the clipboard (conflicts with decisions 16 and 36), gives no in-app selection UI, and it is unverified whether the recurring permission exemption applies when Frisket launches it | — | **Keep own overlay** |

### 1.6 Feature-level verdict (what to keep, simplify, or let the platform do)

| Feature | Verdict | Why |
|---|---|---|
| Area, window, full, scrolling capture | Keep | Core value. Every compared tool has all four; reviewers call scrolling capture "the obvious reason to pay" |
| Pending thumbnail with Copy/Save/Edit/Drag | Keep; fixed-size cards, CleanShot-style hover actions | Reviewers call CleanShot's overlay "the centre of the app"; Frisket's accessibility labels are better, so keep them |
| Solid redaction (guaranteed black) | **Keep as the differentiator** | CleanShot only offers colored fills and pixelate; Frisket passes `--verify-redacted` under blur and magnify |
| Editor | Keep, but native rendering and always-visible exits | Markup hand-off is private API (O18) |
| Copy Text (OCR) | Keep Vision; make it non-modal and never clear the clipboard | Concealment requirement (O19) |
| History (30 d / 1 GB archive with its own window and actions) | **Simplify**: keep retention, simplify storage (O5), make "Restore to card" the primary action | CleanShot's History is a restore buffer (3-day default, up to 1 month); comparable apps use plain GRDB and files |
| System screenshot shortcut takeover | **Replace** with read-only detection plus a deep link (O7) | No comparable tool writes the plist; the manual path is Apple's documented one |
| Byte budgets and 57,600-row cap | **Simplify** to a 32,768-px cap (O14) | Removes the need for the custom encoder |
| Local diagnostics and latency log | **Replace or cut** (O17) | Never read; `os.Logger` covers decision 25 |
| Repository fence, red team, manual checks | **Slim**: invariant checks in `scripts/ci.sh` and a pre-push hook, plus the live harness (O12, O15) | They missed every live bug; the harness caught them |
| Long onboarding and settings essays | Simplify into first-use tips | CleanShot shows a short tip the first time a feature is used |
| After-capture action matrix, pins, upload, recording | Defer (not v1) | Outside decisions 2 and 3; the action matrix is a candidate for later |

---

## 2. Decisions that need recording or amending

**Status: all DA items below were recorded as decision 57 on 2026-09-24, under Prateek's delegation. Phase −1 needs no further sign-off; it only needs the spec deltas and tickets.** Decision 54 lets the coordinator pick the best-evidenced option and record it. Architecture-wide changes still go through spec and tickets. Decisions Prateek made himself (55, 7/8, 28) and the red team's unanimous commit protocol need **his sign-off**. All of these are handled in Phase −1, before any code changes.

| DA | Topic | Current decision | Proposed | Who decides |
|---|---|---|---|---|
| DA-1 | Renderer fence | The core renderer may import only Foundation (`check_repository.py:203-205`) | Allow CoreGraphics, CoreText, ImageIO and Accelerate (vImage) in `FrisketCore` rendering. Keep a ban on `CGImageDestinationCreateWithURL` (the core does no disk I/O). Redaction invariants stay pixel-tested | Coordinator plus a spec delta |
| DA-2 | System shortcuts (dec. 55) | Frisket turns off 28–31, 181, 182 and 184 on collision, at every launch | Keep the ⌘⇧ defaults and Carbon registration. **Stop writing `com.apple.symbolichotkeys`.** Detect the collision read-only, say which macOS shortcuts must be off, and deep-link to System Settings › Keyboard › Keyboard Shortcuts › Screenshots (the Snapzy and CleanShot approach, and Apple's documented path). An **opt-in** "Restore macOS shortcuts" button restores what Frisket's record says it turned off; the record is empty on this Mac, so the README gives the manual steps | **Prateek** (amends his dec. 55) |
| DA-3 | Editor drag finalize (dec. 17) | A drag finalizes when it starts | A drag finalizes when a destination accepts the promise (the promise-written event reaches the coordinator); a cancelled drag leaves the capture pending, with nothing on disk | Coordinator |
| DA-4 | History model (dec. 5, 18, 20) | 30 d / 1 GB archive; SQLite, sidecars and a ledger; fsync-heavy | **Recommended:** keep 30 d / 1 GB. Use atomic PNG writes, GRDB rows at default durability (Snapzy/Capso pattern), and a launch sweep that **adopts** UUID-named orphan PNGs rather than deleting them. Remove the sidecar JSON, auxiliary ledger, `F_FULLFSYNC` chain and flock (see DA-11). Row Delete asks for confirmation. **Fallback:** freeze the current store and fix only D19, D24 and performance | Coordinator plus a spec delta (with DA-11) |
| DA-5 | Notices | Several paths, including modal success | A non-modal notice service; modals only for destructive or irreversible choices | Coordinator |
| DA-6 | Budgets (`CaptureBudgets.v1`) | Encoded byte budgets; a 57,600-row scrolling cap | An output-height cap of 32,768 px (Snapzy precedent; CG/ImageIO-safe) plus measured peak memory. Encoded size is used only for History admission (decision 27) | Coordinator plus a spec delta |
| DA-7 | Process (dec. 7, 8, 45–53) | Red team plus ticket, review and manual-check gating; Codex leads | Local `scripts/ci.sh` plus a pre-push hook plus the automated live harness gate merges. Archive `.scratch` process artifacts outside the main tree. Hosted CI only once the repo is public (decision 9 forbids paid overages; private-repo macOS runners bill at 10×) | **Prateek** (amends dec. 7/8) |
| DA-9 | Scrolling panel keyboard (dec. 24 vs D11) | The panel takes key on every preview, eating Page Down and Space | The panel never takes key, so the page keeps keyboard scrolling. Keyboard Done is **⌘⇧6 pressed again** (the Carbon hotkey is already registered). Cancel stays a VoiceOver-reachable button, and Esc works once the user clicks the panel. No global monitors (fence invariant 5) | Coordinator |
| DA-10 | "Restore to card" vs dec. 28 (no History re-editing) | History rows have their own Copy/Save/Delete | History rows gain "Restore to card". A restored card is already committed: its timeout doesn't commit again, and Edit is disabled. It reuses only Copy/Save/Drag/Copy Text | **Prateek** (touches dec. 28) |
| DA-11 | History commit protocol (red-team consensus) | `F_FULLFSYNC`, `renamex_np`, sidecars, ledger, flock | GRDB at default durability plus atomic PNG writes (SQLite is crash-durable at default `synchronous`) | **Prateek** (amends the unanimous red-team protocol) |

---

## 3. Sequenced work plan

Every phase is test-first: a failing test that reproduces the defect is written before the fix. Phases are sequential except where a note says a step can run in parallel. Each phase ends with its exit criteria, and later phases can be revised at the gates marked ◆.

### Phase −1: Decisions and sign-off (XS, no code)

1. Record DA-3, DA-5 and DA-9 as numbered decisions, under the coordinator's authority (decision 54).
2. Ask Prateek to sign off on DA-2, DA-7, DA-10 and DA-11. Until he signs, Phase 1 applies only the D13 interim below. DA-4 and DA-5 wait for DA-10 and DA-11; everything else proceeds.
3. DONE: spec deltas written (`spec.md` stories 82–101 plus remediation seams). DONE: tickets 42–83 in `.scratch/screenshot-mvp/issues/` (decision 58, which also records four changes to Phase 1):

   | Phase | Tickets |
   |---|---|
   | 0 | 42 build graph · 43 CI and known defects · 44–47 red tests (edited output; choosing what to capture; scrolling; lifecycle and History) · 48 live harness |
   | 1 | 49 window (D2) · 50 overlay clicks (D4, D14) · 51 Loupe (D26) · 52 saved edits interim (D1) · 53 action bar (D5) · 54 drag (D7) · 55 empty Copy Text (D8) · 56 fixed Thumbnails (D9) · 57 History Delete (D10) · 58 Try Again (D19) · 59 reentrancy (D25) · 60 crop (D18) · 61 scrolling keys (D11) · 62 ⌘⇧2 (D12) · 63 macOS shortcuts (D13, full DA-2) · 64 stitch stopgap ◆ A |
   | 2 | 65 renderer: crop and redaction · 66 annotations (D6) · 67 effects, delete encoder ◆ B · 68 preview parity (D23) · 69 `NSUndoManager` |
   | 3 | 70 matcher · 71 slow down · 72 pixel cap (D20) |
   | 4 | 73 Pending capture record · 74 History rows · 75 Region request · 76 notices · 77 adapters product |
   | 5 | 78 History storage · 79 Restore to Thumbnail · 80 slim checks · 81 polish (D15–D17) · 82 docs |
   | 6 | 83 acceptance (ready-for-human) |
4. Rebase or close `.worktrees/ticket-40`: it predates `3d43926`, so acceptance there would test the old stitcher.

**Exit:** the decisions are recorded with their authority; the tickets exist.

### Phase 0: Guardrails and reproduction (S–M)

1. **Build graph, step 1 (O13).**
   - Replace the Xcode `FrisketCore` static-library target (`pbxproj:26-27`) with the SwiftPM product.
   - Keep one GRDB pin and one `Package.resolved`.
   - Use `SDKROOT = macosx`.
   - Move signing into an untracked `Signing.xcconfig`. Keep a documented fallback: an ad-hoc signature resets the Screen Recording grant on every rebuild (decision 49), so the README says so.
   - `FrisketAdapters` stays compiled by the app for now (step 2 is in Phase 4).
2. **Local CI.**
   - `scripts/ci.sh` runs `swift test`, the Xcode build and the checks, plus a pre-push hook that calls it.
   - **Port the "Reject Event Taps and Global Monitors" check into `ci.sh` before removing the every-build script phase** (`pbxproj:14-16`).
   - Add the no-network rule.
3. **Red tests for every defect (none of these exists today):**
   - **D1:** property test: `forEachStrip` output == `render` for random documents containing every annotation and effect kind, at several strip heights and image heights (8–2,000 px).
   - **D1 and D23:** decoded saved output == preview render at scale 1 and 2 (`EditorRedactionCommandsTests`).
   - **D2:** a `WindowSelection` fixture with an empty-bundle cursor window at layer 2147483630 above a normal window. Keep `foreignFloatingWindowIsCapturedAheadOfOverlappingNormalWindow` green.
   - **Exclusion list:** regression tests that the exclusion list (decision 37) and Frisket's own windows are excluded in area, full, window and scrolling capture.
   - **D3:**
     - test the round trip through `ScrollingCaptureSession.ingest` (the production seam; start from the loops on branch `diagnose/red-loops`, commit `4869429`, minus the `[DEBUG-d3h]` probes). Do not restore the old `stitch(expectedStep:)` tests, which skip the delta search;
     - fix `TestImageFactory.repeatedScrollingFrame(period:)`;
     - add a synthetic-page round trip: slice with random steps, including uniform and repeating bands and a flick, then stitch back; the result must equal the page (reuse `RecordedScrollSequence.validationIssues`).
   - **D7:** a real `DragStagingLifetime` with a session that ends without a promise write, which must leave no file and no commit. Replace the `RecordingDragHandoff` fake, which always fires both events.
   - **D8:** empty OCR leaves the clipboard unchanged (change count and contents).
   - **D18:** fix the expectation in `fractionalCropAndRedactionSnapOutwardAfterCropAndScale`.
   - **D19:** after `recoverHistory()`, `delete` and `finalizedImage` succeed.
   - **D20:** a 5K 2× frame size sequence must not stop before the pixel cap.
4. **Promote the live harness.** Move `/tmp/frisket-beta` into `Tools/LiveHarness/`:
   - the pattern tool with a display option;
   - the `drive` CLI, with its focus guard and an all-displays bounds check;
   - `scan` and `redink` pixel meters, and the scroll-page flip fix.
   - Write a scripted "beta matrix" that reruns the §1.2 live checks.
   - The CleanShot comparison was a one-off (done 2026-09-24); it is rerun only if a parity question comes up.

**Exit:** `ci.sh` is green on existing tests; every new D-test is red for the right reason; the harness reruns the matrix unattended.

### Phase 1: Correctness hotfixes (S; each is 1–30 lines)

This phase ships value before the re-architecture. The steps are independent and can run in parallel, except that D7 and D11 need their decisions from Phase −1. D5 (interim) and D6 (interim) are cheap stopgaps that Phase 2 replaces. D9 skips its stopgap and goes straight to fixed-size cards (O10).

| Fix | Change |
|---|---|
| D1 (interim) | When edits exist and the output is under the cap, run `DocumentRenderer.render()` on the whole image and slice it for the encoder; keep strips only for outputs above the cap. A per-strip halo can't be correct: magnify reads rows up to half the box height above the strip (`DocumentRenderer.swift:226`), and blur chains 6 passes (`:176`). The strip == render property test carries into Phase 2 |
| D2 | `WindowSelection`: reject an empty bundle ID, apply a level ceiling below Dock/pop-up/cursor levels, require width and height ≥ 32 pt, exclude the Dock bundle (Capso #294). Keep own-app exclusion and floating-window support. Map selection failure to a correct message |
| D3 (stopgap) | In `ScrollingCaptureStitcher.searchDelta`, choose the best score over all deltas, not the first zero. Sample every 4th column instead of 24 in total. Treat near-identical frames as no movement. When an alignment is ambiguous, wait for the next frame; on one failure, keep the accepted prefix (`ScrollingCaptureSession.swift:187-194`) |
| D4 and D14 | Explicit `panel.ignoresMouseEvents = false` on both overlays (Capso's design); closed-interval display containment (`NSMouseInRect` semantics) |
| D5 (interim) | `visibilityPriority = .high` on the Done, Copy and Save items; route ⌘C, ⌘S, Return and ⌘Z through menu or responder actions, not the button views |
| D6 (interim) | The guide shows exactly the glyphs that will be drawn (dropped characters are visible while typing) until O1 lands |
| D7 (DA-3) | The coordinator commits when it receives the promise-written event (`DragCopyEvents`), not at drag start. In the same change, delete `DragStagingLifetime`'s disk staging; write the promise from memory |
| D8 | Empty OCR → no pasteboard write, and a non-modal "No text found" on the card status line |
| D9 → O10 | Fixed-size cards (image aspect-fit inside) with a simple cumulative stack, instead of patching the variable-height maths |
| D10 | Delete confirmation. If the capture's card is open, close the card first (commit), then delete; the message never says "Try again" for a state retrying can't fix |
| D11 (DA-9) | The scrolling panel never becomes key; ⌘⇧6 again = Done. Matches Phase 3 |
| D12 | Thumbnail panel `.nonactivatingPanel`, becoming key on ⌘⇧2, with a visible focus ring |
| D13 (interim) | Remove the claim call from `applicationDidFinishLaunching` (no re-disable at launch). Surface errors instead of `try?`. The rest of DA-2 waits for sign-off |
| D18 | `originX = floor(crop.x * scale) / scale` (and the same for Y); update the locked test |
| D19 | Reopen the writer after a successful recovery (or have `delete` and `finalizedImage` open it on demand) |
| D25 | Set `inProgress` for `.deleteHistory` and OCR; quit continues past captures it can't finalize |

**Exit:**
- **Green:** D1 (interim), D2, D3 (stopgap), D4, D5 (interim), D7, D8, D9/O10, D10, D11, D12, D13 (interim), D14, D18, D19, D25; the live matrix passes these rows on both displays.
- **Known-red, tagged** in the test names: D3 (full round-trip with a flick), D6, D20, D21, D22, D23, fixed in Phases 2–3.

◆ **Gate A:** **Removed by decision 60** (scrolling capture removed, ticket 87). Was: after the D3 stopgap, measure it on the harness page (target 400/90/90/8, as CleanShot achieved) and decide the scope of the O4 rework.

### Phase 2: Native rendering and editor (M–L)

- **O1 renderer.** It needs DA-1 and DA-6. The interface is the design-it-twice hybrid (the four designs and the comparison are in `Plans/2026-09-24-session-handoff.md`):
  - `CaptureFlattening.flatten(_ capture: Data, edits: DocumentEdits) throws(RenderFailure) -> Data` is the only output path (Done, Copy, Save, drag, History, OCR input). The coordinator's single real seam uses `CaptureRenderer` in production and a `ScriptedFlattener` in tests, replacing `RejectOnceCodec` and `LoopCodec`; `codec:` becomes `flattener:`.
  - `CaptureRenderer.preview(_ capture: Data, maxEdge: 2048) -> CapturePreview`, and `CapturePreview.render(edits) -> CGImage` takes the same edits as Done. Contract: at maxEdge ≥ output size, `render(edits)` equals `decode(flatten)`. When downsampled, blocks touching a redaction stay exact black (concealment wins).
  - `RenderFailure.outputTooTall` is thrown before any allocation. Annotations stay drawn on top of redactions, as today.
  - No internal ports: pixel backend, encoder and text shaping are rejected as single-adapter seams. Per-effect row footprints and a tile pipeline are an internal Gate B fallback only.
  - Deletes `DocumentRenderer`'s public API, `StripPNGEncoder`, `AnnotationFont`, `EditorProxy`, `PNGBitmapCodec`, and `Bitmap`/`EditorDocument`/`BitmapCodec`.
  - Must land with DA-6, whose 32,768 cap conflicts with `scrollingPixelCap` 57,600 and `EditorMemoryRunTests`.
  - If `flatten` goes async, insert `inProgress` before the await.
  - Render the whole output into one sRGB `CGContext` (≤ 32,768 px tall by DA-6), using CoreGraphics strokes and CoreText labels at 18 pt. The label seam agreed in `next-session.md` becomes unnecessary once text is drawn by CoreText.
  - Blur via **vImage with edge-extend, clamped to its box** (`DocumentRenderer.swift:152-153` semantics). This is deterministic on x86_64 and arm64 (decision 56 beta testers); Core Image is not. Magnify via CoreGraphics on the full effect box.
  - Redaction as an opaque, copy-blend, non-antialiased fill, stamped before and after effects (unchanged invariant).
  - **Privacy checklist**, written as tests before the swap:
    1. Crop is integer-aligned and drawn with `interpolationQuality = .none`, so no resampling can smear pre-redaction pixels into the border (the D18 class).
    2. Redaction goldens are byte-exact on both architectures.
    3. Blur and magnify never read outside their box or under a redaction.
    4. A fixed sRGB working colour space everywhere.
    5. OCR reads only the rendered result.
    6. Off-main render tasks release the original on Delete or Close (decisions 16 and 31).
    7. The PNG carries no metadata.
  - Encode via `CGImageDestination` to in-memory `Data` (never to a URL in the core).
  - If measured peak memory at 5120 × 32,768 is over budget, fall back to per-strip `CGContext`s that translate by `rowShift`, feeding a strip-backed `CGDataProvider`. ImageIO row streaming is unverified, so measure it first.
  - Delete `StripPNGEncoder.swift`, `AnnotationFont.swift`, the `@_silgen_name` declarations and the `z`/`compression` linker flags.
  - Update `check_repository.py:203-205` (or its slim successor, O12) to the DA-1 fence.
- **Preview parity.** The preview uses the same renderer at the preview scale. Redaction rectangles are computed in output pixels, then mapped to the preview (D23).
- **O8 editor chrome.** A content-area action bar (Done, Copy, Save, Drag handle; CleanShot-style), with tools in the toolbar. **O11:** `NSUndoManager`. Tools stay reachable by keyboard; label field behavior is unchanged (C was refuted).
- **Off-main work.** Editor re-render and thumbnail decode move to a background task; the main actor only swaps images.

**Exit:** the D1, D6, D18, D21, D22 and D23 tests and the privacy checklist are green through the native path; `EditorMemoryRunTests` is under budget at 5120×32,768; the live matrix passes on both displays. ◆ **Gate B:** if peak memory fails, switch to the per-strip `CGContext` fallback before deleting the old encoder.

### Phase 3: Scrolling capture rework (M–L; scope set at Gate A)

**Removed by decision 60.** Scrolling capture was removed (ticket 87; tag `scrolling-capture-last`). Tickets 64, 70, 71 and 72 are withdrawn. The text below is kept as history.

- **Matcher (O4).**
  - Candidate delta from Vision `VNTranslationalImageRegistrationRequest` on downsampled frames (the macshot/Capso/ScrollSnap approach), verified by a dense pixel score (all columns, or strided ≥ 1/4) over the overlap.
  - Reference implementations to read, not copy (licences differ):
    - macshot `ScrollCaptureController.swift` and `ScrollFrameAnalyzer.swift` (GPL-3: read only);
    - Capso `Scrolling/ScrollCaptureController.swift`;
    - Snapzy `docs/SCROLLING_CAPTURE.md` (BSD-3), for the expected-delta guidance and sticky-header handling.
  - Choose the **best** score, not the first zero.
  - Detect uniform bands: an ambiguous overlap means "wait for the next frame", not "append".
  - Sticky header and footer detection requires agreement across 2 or more frames.
- **Session.**
  - Treat near-identical frames as no movement (tolerance, not byte equality).
  - On a single alignment failure, keep the accepted prefix and prompt the user.
  - Show a "Slow down" hint when the measured delta is at least 0.8 × the viewport.
- **Capture.**
  - Reuse `SCShareableContent` between environment-generation changes instead of fetching it per sample; adopt an `SCStream` only if the measured sampling rate is too low.
  - The panel never takes key (DA-9). Cancel and Done sit in place next to the region; ⌘⇧6 again = Done.
- **Memory (O14/D20).**
  - An incremental downsampled preview (append only the new rows).
  - A pixel-height cap; encoded size is only a warning; a PNG over the output limit is still delivered to the clipboard or Save, just not History (decision 27 semantics).
- **Docs.** Rewrite `docs/stitcher.md`; delete the Vision probe leftovers, or make them real.

**Exit:** the synthetic round-trip property test passes; on the harness page the live result matches CleanShot (400/90/90/8); a 5K 2× sequence reaches the pixel cap without a budget stop.

### Phase 4: Architecture and modularity (M)

- **`CaptureLifecycleCoordinator` (architecture candidate #2).**
  - A `[CaptureID: PendingCapture]` record plus a settled map replace the ~13 parallel collections. There are no `editing` or `delivering` states: the core never sees editing, and delivering is a transient lock.
  - `thumbnails()` returns a public status per Thumbnail, plus `nextDueAt`.
  - `.drag` goes through `deliver()` and commits once the promise is written (candidate #4).
  - Delete the Middle Man `CaptureCommandLayer` and the History pass-throughs; the History window reads `HistoryStore.rows()` directly (candidate #5).
- **`CaptureSurfaces`.** It applies the core's Thumbnail status, lays out fixed-size Thumbnails, and keeps only `notice(for:)`. Delete the `arrivalOrder` and `screens` shadow copies. Do not split out `EditorSessions` or `CaptureLauncher`; they would share `panels` and each would be shallow.
- **`AppController`.** Extract `NoticeCenter` (O9) and `TerminationCoordinator` only; split further only if a change needs it.
- **`HistoryStore` (gated on DA-4 and DA-11; no split of the current design).**
  - **If DA-4 is recommended:** Phase 5 rewrites a smaller store. Here, only the O(n²) window reload is fixed: lookups by ID, a thumbnail cache, a lazily loaded list.
  - **If fallback:** the same performance fixes plus batch eviction with one checkpoint.
- **Region request (candidate #7).** One `RegionCapture` (`select`/`capture`) that caches shareable content per environment generation. The core computes a `RegionRequest`, and `CaptureImage` carries `displayID`. It replaces the 7-step ordering, the copied scrolling geometry and the `captureDisplayID` side channels. `WindowSelection(rows:)` owns the listing join and filter (candidate #6).
- **Preference keys.** One enum; drop the never-released ⌃⌥⌘ migration.
- **Build graph, step 2 (O13).** Expose `FrisketAdapters` as a package product (make the needed adapter types `public`); the app stops compiling `Frisket/Adapters` itself.
- **Tests.** Thumbnail status assertions at the existing command test surface replace the planned presenter tests (replace, don't layer).
- **Concurrency hygiene.**
  - Remove the unneeded `@preconcurrency` imports.
  - Drop `Sendable` from the stitcher and session (actor-confined).
  - Replace force unwraps with `HistoryFailure`.

**Exit:** the coordinator holds one per-capture record; the Thumbnail status is tested through `thumbnails()`; `CaptureCommandLayer` is gone; the live matrix is still green. There is no blanket line-count gate.

### Phase 5: Simplification and scope decisions (S–M; needs DA-2, DA-4, DA-7, DA-10, DA-11 signed)

- **O7 / DA-2:**
  - Delete the write path in `SystemScreenshotHotkeyStore.swift`, including `notify_post` via `@_silgen_name`.
  - Keep `SystemShortcutReader` for read-only collision detection.
  - Settings shows "macOS still owns ⌘⇧4" with an "Open Keyboard Shortcuts…" button (deep link to System Settings).
  - An **opt-in** "Restore macOS shortcuts" button restores what Frisket's record says it turned off. It is never automatic, because that would take ⌘⇧3/4/5 back from Frisket.
- **O5 / DA-4 and DA-11 (recommended option):**
  - Collapse to atomic PNG writes, GRDB rows at default durability, and a launch sweep that **adopts** UUID-named orphan PNGs (size read from the file) rather than deleting them. This replaces the sidecar adoption in `HistoryStore.swift:132-148`.
  - Migrate with a GRDB migration plus the file deletions.
  - The pre-migration backup is Time Machine-excluded (decision 35) and deleted after the post-migration check passes.
  - **DA-10:** add "Restore to card" (committed state; Edit disabled; timeout doesn't recommit) and confirmed Delete in the History window.
  - Fallback: freeze the store and fix only D19, D24 and performance.
- **O12:**
  - Keep the six named invariants from §1.5 O12 in a slim `Checks/` script run by `ci.sh` and the hook. Compiler-enforce what SwiftPM target boundaries can.
  - Delete the regex rules that became redundant, the Snapzy provenance and identity checks, and the three `stitcher-*` fixtures.
  - SwiftLint is optional, not required.
- **Dead code** (audit list §1.4):
  - Vision probe, stitcher leftovers, test-only public API, `outputCount`;
  - empty `discardSelectionPreviews` and `FrisketCore.swift`;
  - unread diagnostics (inject one sink, or delete);
  - `build-snapzy.sh` and the snapzy branch in `measure.py`.
- **Docs.**
  - Rewrite `stitcher.md` and `core-package.md`; retire `SESSION-CHECKPOINT.md` into `docs/history/`.
  - Update `cursor-workflow.md` and the manual checks to ⌘⇧ shortcuts.
  - Shrink the manual checks to what the live harness can't automate.
- **Process (DA-7).** Archive `.scratch/red-team`, `reviews/` and `reports/` outside the main tree; delete the `.worktrees/ticket-40` after rebasing or closing ticket 40.
- **Polish (D15–D17).**
  - Windows open on the active display with correct initial focus.
  - Accessibility: committed-card title and actions; a single label per row; picture element.
  - Save confirmation and dated file names.
  - About rendered as attributed text.
  - Menu item enablement.
  - Consistent ⌘⇧ order.
- **Optional, CleanShot-inspired:** a small after-capture action preference, and per-feature first-use tips instead of long onboarding text.

### Phase 6: Acceptance (S–M)

- `scripts/ci.sh` green; the live-harness beta matrix green on both displays; the §1.3 CleanShot rows marked met or intentionally different (no rerun needed unless disputed).
- Run the manual checks the harness can't automate: permissions (missing and revoked), logout and lock, display unplug, first launch.
- Re-measure performance: `Tools/Performance`, capture→thumbnail latency, and the editor memory run at 5120×32,768.
- Close ticket 40 on the rebased tree. Confirm that every DA-n is recorded in `decisions.md`.

---

## 4. Verification strategy

| Layer | What proves it | Where |
|---|---|---|
| Unit and property | Strip == full render; saved == preview; stitch round trip; window filter; drag cancel; empty OCR; recovery reopen | `Tests/FrisketCoreTests`, `Tests/FrisketAdapterTests` |
| Pixel golden | `--verify`, `--verify-full`, `--verify-redacted`, plus the ink-band meter (`redink`) and block meter (`scan`) | `Tools/LiveHarness` |
| Live matrix | Area, window, full, scrolling (steady, flick, up), editor (arrow, text, redaction, blur, magnify, crop, undo, close sheet), OCR (text/none), stack, History (copy, save, delete), ⌘⇧2 focus, top-row pointer, both displays | `Tools/LiveHarness/beta-matrix.sh` (focus-guarded; clipboard saved and restored) |
| Comparator | One-off CleanShot X benchmark (done 2026-09-24, §1.3); rerun from its menu only if a parity question comes up (URL API stays off) | Same harness |
| Local CI | `swift test`, Xcode build, the invariant checks, no-network rule | `scripts/ci.sh` plus a pre-push hook; hosted CI only after the repo is public (DA-7) |

---

## 5. Risks and mitigations

- **Renderer swap changes pixels.** The privacy checklist tests (Phase 2) and byte-exact redaction goldens are written first; antialiasing is allowed only for annotations; redaction stays non-antialiased copy-blend.
- **Cross-architecture pixel drift.** Goldens must pass on arm64 as well as x86_64. vImage blur is deterministic, while Core Image and text antialiasing are not. Annotation goldens therefore use a tolerance, and redaction goldens are exact. No Apple-silicon Mac is available here, so ask a beta tester (decision 56) to run `ci.sh`.
- **The whole-image CG path may use more memory than the strip encoder.** Measure with `EditorMemoryRunTests` at 5120×32,768 before deleting the old encoder; Gate B's fallback is per-strip `CGContext`s.
- **Vision registration fails on low-texture pages.** Always verify with a pixel score; when both are ambiguous, wait for the next frame. Flat content also defeats Snapzy, macshot and CleanShot, so the retry UX matters more than the algorithm.
- **DA-2 removes the automatic takeover.** On a fresh Mac, ⌘⇧3/4/5 go to macOS until the user turns them off; the first launch explains this and deep-links to System Settings.
- **History migration.** Adopt orphan files rather than delete them. Keep the backup Time Machine-excluded and delete it after the check. Migrate only after DA-4 and DA-11 are signed.
- **Beta testers on other Macs.** Signing moves to xcconfig; the README documents that an ad-hoc or unsigned build resets the Screen Recording grant on every rebuild.

---

## 6. Out of scope (kept deferred)

Screen recording, cloud upload, pins, URL or App Intents automation (decision 19), sandbox and notarization, arm64 execution testing (no Apple-silicon Mac here), and localization beyond extracting strings into a catalog.

---

## Appendix A: Evidence and artifacts

- Live notes: `.scratch/visual-pass/beta/0-summary.md` and files 1–4; evidence PNGs in `.scratch/visual-pass/beta/evidence/` (gitignored).
- Harness binaries (temporary): `/tmp/frisket-beta/{pattern,drive,cardact,wheel,scan,redink,px,sck,cstype}` with Swift sources.
- CleanShot comparison outputs (temporary): `/tmp/frisket-beta/cs-scroll.png` (exact stitch) and `cs-annot-out.png` (annotations faithful).
- State left behind by testing:
  - Frisket History test captures (the 4 pre-test captures are untouched), and a 744 B test PNG in `staging/drag/` (D7 evidence);
  - test exports `~/Pictures/Frisket/Frisket-812101E6-…-r1.png` and `Frisket-29E0BDAC-…-r2.png`;
  - 12 CleanShot test captures (they expire in 3 days).
  - The clipboard was restored and all system settings are unchanged.

## Appendix B: Research sources

Items the research could not verify are marked "(unverified)".

**Apple:**
- [SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager) and [captureImage(in:)](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage(contentfilter:configuration:completionhandler:))
- [SCScreenshotConfiguration](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration) (macOS 26)
- [SCStreamConfiguration.showsCursor](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/showscursor)
- [SCWindow](https://developer.apple.com/documentation/screencapturekit/scwindow)
- [SCContentSharingPicker](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker) and [WWDC23 10136](https://developer.apple.com/videos/play/wwdc2023/10136/)
- [VNTranslationalImageRegistrationRequest](https://developer.apple.com/documentation/vision/vntranslationalimageregistrationrequest)
- [ImageAnalysisOverlayView](https://developer.apple.com/documentation/visionkit/imageanalysisoverlayview)
- [CGImageDestination](https://developer.apple.com/documentation/imageio/cgimagedestination) (no row streaming)
- [NSToolbarItem.visibilityPriority](https://developer.apple.com/documentation/appkit/nstoolbaritem/visibilitypriority-swift.property)
- [NSSharingService.Name](https://developer.apple.com/documentation/appkit/nssharingservice/name) (no public Markup)
- [macOS screenshot shortcuts, manual change path](https://support.apple.com/guide/mac-help/keyboard-shortcuts-mchlp2262/26/mac/26)
- [Screenshot app](https://support.apple.com/en-us/102646)

**SQLite durability:** [pragma synchronous](https://www.sqlite.org/pragma.html)

**Open-source tools:**
- Snapzy ([repo](https://github.com/duongductrong/Snapzy)): [CAPTURE.md](https://raw.githubusercontent.com/duongductrong/Snapzy/HEAD/docs/CAPTURE.md), [SCROLLING_CAPTURE.md](https://raw.githubusercontent.com/duongductrong/Snapzy/HEAD/docs/SCROLLING_CAPTURE.md), [HISTORY.md](https://raw.githubusercontent.com/duongductrong/Snapzy/HEAD/docs/HISTORY.md), [SystemScreenshotShortcutManager](https://raw.githubusercontent.com/duongductrong/Snapzy/HEAD/Snapzy/Services/Shortcuts/SystemScreenshotShortcutManager.swift), [PR #609 (flat-content stitch)](https://github.com/duongductrong/Snapzy/pull/609)
- macshot ([repo](https://github.com/sw33tLie/macshot), GPL-3): [ScreenCaptureManager](https://raw.githubusercontent.com/sw33tLie/macshot/HEAD/macshot/Capture/ScreenCaptureManager.swift), [ScrollCaptureController](https://raw.githubusercontent.com/sw33tLie/macshot/HEAD/macshot/Capture/ScrollCaptureController.swift), [HistoryStorage](https://raw.githubusercontent.com/sw33tLie/macshot/HEAD/macshot/Services/HistoryStorage.swift), [#386](https://github.com/sw33tLie/macshot/issues/386)
- Capso ([repo](https://github.com/lzhgus/Capso)): [CaptureOverlayWindow](https://raw.githubusercontent.com/lzhgus/Capso/HEAD/App/Sources/Capture/CaptureOverlayWindow.swift), [WindowInfo](https://raw.githubusercontent.com/lzhgus/Capso/HEAD/Packages/CaptureKit/Sources/CaptureKit/WindowInfo.swift), [AnnotationRenderer](https://raw.githubusercontent.com/lzhgus/Capso/HEAD/Packages/AnnotationKit/Sources/AnnotationKit/AnnotationRenderer.swift), [#294 (Dock as window)](https://github.com/lzhgus/Capso/pull/294)
- [ScrollSnap releases](https://github.com/brkgng/ScrollSnap/releases) (moved to Vision)
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
- ShareX history ([JSON](https://raw.githubusercontent.com/ShareX/ShareX/develop/ShareX.HistoryLib/Managers/HistoryManagerJSON.cs), [SQLite](https://raw.githubusercontent.com/ShareX/ShareX/develop/ShareX.HistoryLib/Managers/HistoryManagerSQLite.cs))

**CleanShot X:**
- [features](https://cleanshot.com/features), [changelog](https://cleanshot.com/changelog), [URL API](https://cleanshot.com/docs-api)
- [TIL: using the default shortcuts with CleanShot](https://github.com/jbranchaud/til/blob/master/mac/use-default-screenshot-shortcuts-with-cleanshot-x.md) (community, not official)
- Reviews: [ThinkDifferent](https://www.thinkdifferent.blog/blog/cleanshot-x-measured/), [MakerStack](https://makerstack.co/reviews/cleanshot-x-review/)

**Unverified:**
- whether `SCContentSharingPicker` still needs the Screen Recording grant on macOS 26;
- whether `screencapture` launched by Frisket is exempt from the recurring permission prompt;
- whether the private Markup service works on macOS 26;
- whether ImageIO streams a sequential `CGDataProvider`;
- whether `SCScreenshotConfiguration` behaves as documented in practice.
