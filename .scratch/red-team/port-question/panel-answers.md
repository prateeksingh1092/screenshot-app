# Port question: Cursor Opus 5.5 High role answers

Question (Prateek, 23:29 UTC): "Why even port anything from Snapzy, instead of building from scratch?" Prompt: `../prompts/port-question.md`. Codex's answer is in `arch.md`. Condensed faithfully by the facilitator from each agent's final response.

## QA (`f16cf29f-b342-4a51-ae52-f28e4c0e15d8`): C-ref, stitcher exception, medium confidence
- Port nearly verbatim: the stitcher (frames in, image out, already a pure seam) with its byte-exact deterministic tests (`ScrollingCaptureStitcherTests.swift:298-483`) and `TestImageFactory.repeatedScrollingFrame`. Cost: at least 1,667 lines, calls Vision (`:1667`), tests must move from XCTest to Swift Testing, never proven on Intel (CI on `macos-15`).
- Reference only: forced-quit points, crop and coordinate-space cases, multi-monitor stale-state scenario, arrow geometry, render-equivalence and frozen-snapshot patterns, retention scenarios, all rewritten against our seams.
- Porting cost: tests couple to singletons, real clock, real pasteboard, private reflection; some protect behavior contradicting our rules (persisted originals, blur redaction); all 156 import XCTest; renderer tests need teardown-crash workarounds (`AnnotateRenderSnapshotTests.swift:16-18`), so the renderer isn't clean.
- From-scratch cost: a fresh stitcher lacks Snapzy's hard-case knowledge and needs recorded frame sequences (Snapzy's fixture directory is empty); add golden-output tests per case.
- Would change mind: renderer/database extract behind ports in under a day each with passing Swift Testing tests on this Mac (toward B); ported stitcher fails byte-exact tests on macOS 26.7 Intel (toward C-clean).

## DATA (`3f6a5555-a98c-47eb-8ad4-466e20029e9d`): C-ref for persistence, high confidence
- Port: almost nothing; only patterns: typed-error open/migrate with archive recovery (`DatabaseManager.swift:23-47, 256-298`, minus `eraseDatabaseOnSchemaChange` and the cloud table), per-process test database isolation (`152-161`), GRDB `ValueObservation` (documented GRDB API anyway).
- Reference: its failure modes (non-atomic trim `CaptureHistoryStore.swift:516-535`; thumbnail sweep name mismatch; path-prefix ownership) and test scenarios to invert or extend.
- Porting cost: schema lacks lifecycle state and ownership, stores absolute paths, text UUID primary key, unused `isDeleted`, video/GIF types; retention deletes rows and files separately. Adaptation rewrites most of each file while still owing attribution.
- From-scratch cost: very little; GRDB supplies pooling, migrator, observation; ~300 lines of fresh store and recovery code.
- Would change mind: a Snapzy file already implementing a transactional two-state lifecycle keyed by UUID (none found).

## UX (`2fde8f32-9f18-43df-a854-1a693065d40c`): C-ref for all UI, medium confidence
- Port: almost none. Maybe the system-shortcut reader (`SystemScreenshotShortcutManager.swift:88-93,157-191`), made fail-closed; the display re-anchor rule is easier to rewrite.
- Reference: overlay workarounds (`AreaSelectionWindow.swift:103-110,237,250,735-743,1025`) as decision-23 checklist cases; relaunch-required permission probe (`ScreenCaptureManager.swift:183-246`); rebuild-signing note (`AppIdentityManager.swift:25-28`); panel Spaces setting; Reduce Motion fallbacks.
- Porting cost: the thumbnail is pointer-centric (cannot become key; hover-only actions), conflicting with decision 24; the 4,672-line overlay is tangled with recording, smart-element and passthrough modes; sparse editor accessibility; onboarding lacks a history-disclosure step.
- From-scratch cost: rediscovering multi-display and focus bugs that need real hardware; reading Snapzy's comments first cuts most of it.
- Would change mind: a short overlay spike on this Mac that can't make crosshair and Esc work across displays, or evidence the overlay separates cleanly with its tests.

## REL (`b0a2d7aa-d91a-4906-97a3-fb51923a932c`): C-ref, stitcher exception, medium confidence
- Port: `ScrollingCaptureStitcher.swift` (1,757 lines): no GRDB/Sparkle/WebP imports, no localization, preferences, or Snapzy identifiers found. Cost: one header, one provenance entry, one notice line. Coordinator (57 hits) and types (62 hits) are tangled; database layer hard-codes `Application Support/Snapzy/snapzy.db`; renderer defaults the watermark to "Snapzy".
- Reference: self-signed-cert TCC approach (`docs/SELF_SIGNED_CERT.md`), hardened-runtime/sandbox-off config, entitlements as a list of what not to request, fixture ideas. Ideas only; don't copy text.
- Porting cost: headers, provenance sync, identity scrub (blocker given the installed Snapzy benchmark), keeping Sparkle/WebP out, no-endorsement risk; grows per ported file.
- From-scratch cost: little legally (BSD-3 is permissive); closely derived files still get the BSD header. C-clean buys no legal benefit and discards free reference material.
- Would change mind: database and renderer prove as self-contained as the stitcher after a scrub (toward B); stitcher tied to coordinator types (toward C-clean). Checkable by compiling the stitcher alone in a scratch package (not done).

## PERF (`ce8bc2c6-43a6-46ca-b0ba-74f6bf394e1b`): C-ref, alignment-scoring exception, medium confidence
- Port: only the stitcher's pure alignment scoring: static header/footer band detection, block-difference scoring, `bestMatch` search, Vision-assisted delta estimate (`ScrollingCaptureStitcher.swift:122-178, 387-437, 787-843`). Adapt to read strips from a buffer instead of `[UInt8]` copies; BSD-3 attribution owed.
- Reference: scrolling edge cases (partial end steps, height-limit status, frame-stability check `ScrollingCaptureFrameRing.swift:77-110`); forced-quit cases as fixture tests; `CGImageSourceCreateThumbnailAtIndex` for stored files; Carbon hotkeys.
- Porting cost: the parts decision 13 would port hold the round-1 problems: the stitcher keeps every full frame and copies the merged image twice (~5.2 GB for 20 screens at 5K); encodes straight to the final file with the thumbnail after the PNG encode; retention deletes rows before files and its orphan sweep deletes current thumbnails; event taps on the main run loop. Removing them while keeping callers compatible is regression risk that current tests don't cover.
- From-scratch cost: empirical alignment tuning (sticky headers, animation, momentum) that Snapzy already paid for; the reason for the exception. Strip store, finalization, quota, and hotkeys are small and should be designed fresh.
- Would change mind: a spike moving the ported stitcher to strip storage in ~2 days under 2 GB for a synthetic 5120×57,600 capture (toward B for the stitcher); fresh alignment matching Snapzy's accuracy on a small fixture set within a week (toward C-clean).

## PLAT (`33295a27-4b6b-4656-b007-2414d48a183c`): C-ref for all platform code, stitcher exception, medium confidence
- Port: `ScrollingCaptureStitcher.swift` (1,757 lines) imports only AppKit, Foundation, Vision (`:8-10`); no capture, window, or permission calls; fits the decision-14 package behind fixture tests with its BSD-3 header; replace logging and configuration dependencies (inference). arm64 untested.
- Reference: mixed-DPI and multi-display crop rules (`CAPTURE.md:99-102`), Space-drop watchdog (`CAPTURE.md:120-122`), system shortcut collision list (`SystemScreenshotShortcutManager.swift:28-32`), relaunch-after-grant (`ScreenCaptureManager.swift:192-199`), Carbon Fn handling (`KeyboardShortcutManager.swift:1631-1637`), re-signing grant test (`docs/SELF_SIGNED_CERT.md:35-51`).
- Porting cost: macOS 13 target (`project.pbxproj:323`); `CGDisplayCreateImage`/`CGWindowListCreateImage` obsoleted in macOS 15 SDK headers; 20 such calls or `sharingType` uses across the overlay, capture manager, and view model; `sharingType = .none` ignored by ScreenCaptureKit. Porting the overlay (4,672 lines) or capture engine (2,744 lines) rewrites their core while carrying macOS 13/14 fallbacks and out-of-scope features.
- From-scratch cost: re-fixing Space membership, mixed-DPI crops, padded ScreenCaptureKit images, popover retention; C-ref avoids most by reading Snapzy's docs and tests.
- Would change mind: a macOS 26 type-check showing the legacy calls still compile; or evidence the overlay's Space handling separates cleanly from capture calls.

## SEC (`d4211874-a435-4259-81fc-bd5364be1a32`): C-ref, medium confidence (answered 19:02 CDT)
- Port: nothing that touches pixels, clipboard, drag, storage, or logs. The stitcher's matching math is security-neutral; porting it is acceptable but outside SEC's role, provided it takes in-memory frames and writes no temporary files (inference).
- Reference: Snapzy's round-1 failures as ready leak test cases (original-bearing session sidecars, OCR on `effectiveSourceImage`, file URL on the clipboard, drags handing out the source URL, delete-to-Trash; research doc steps 3-7). Reusable techniques: own-app exclusion filter (`ScreenCaptureManager.swift:2691-2718`) and snapping regions to the source pixel grid (`AnnotateAnnotationRenderer.swift:655`).
- Porting cost: every component brings unsafe defaults to find and remove (styled-rectangle redaction `AnnotateAnnotationRenderer.swift:61-76, 277-278`; blur sampling the original `:641-660`; `sharingType = .none` ignored by ScreenCaptureKit on 15.4+; file names and error descriptions in logs `DiagnosticLogger.swift:81-93`, `ClipboardHelper.swift:109`; OCR text in notifications `OCRNotificationContent.swift:28`). Proving a ported path clean means auditing everything it calls; a missed call is a silent leak. Fresh code can build the invariants into types: an opaque redaction type, a pending-capture type that can't be encoded to disk, a logging API without free-text strings.
- From-scratch cost: rediscovering multi-display and scale mismatches, desktop-icon filtering, ScreenCaptureKit hangs (issue #286, `ScreenCaptureManager.swift:2680`), stitch artefacts that could duplicate or misplace redacted rows (inference); more first-time bugs where pixel leaks happen.
- Would change mind (toward B per component): a read-only audit showing the component has no pasteboard, file-system, or logger dependency and already passes SEC-1 opacity tests; or evidence that the capture edge cases take much longer than the audit.

## Outcome (8 of 8)
All eight roles chose C-ref. The only code any role would port is the scrolling stitcher: QA, REL, and PLAT would port the whole file; PERF only its alignment scoring (its frame storage breaks the memory budget); ARCH only after a bounded comparison; SEC is neutral; DATA and UX have no stake.
