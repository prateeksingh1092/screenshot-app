# Independent stack assessment for screenshot-app

Date: 2026-09-22. Status: research recommendation; no stack ADR or foundation acceptance yet.

## Decision

**Recommend Swift with AppKit for capture overlays, floating panels, editor interaction, and system integration; SwiftUI for settings and ordinary library views; ScreenCaptureKit for pixels; Vision for local OCR and optional alignment; Core Graphics/Core Image for compositing; and SQLite metadata with image files outside the database.** This is an architectural judgment for the agreed macOS-only scope, not a benchmark result. It remains the recommendation even if Snapzy fails evaluation.

Snapzy already uses this broad combination, including GRDB over SQLite. That makes its technology choices a strong fit; it does **not** make the existing app an accepted foundation. Its persistent editable annotation sessions retain original image data, whereas this project’s proposed history policy retains finalized images. Its broader recording, cloud, and remote-OCR surface also exceeds v1. Adaptation needs a concrete lifecycle audit and an Intel build/workflow evaluation before acceptance. [Snapzy project configuration][snap-project], [history documentation][snap-history], [annotation persistence implementation][snap-session]

## Scope and method

The approved direction is personal use first, possible later distribution, macOS on the owner’s Intel Mac, area/window/full-screen capture, floating thumbnail with copy/save/drag/edit, annotation and solid redaction, OCR, scrolling capture, local storage, and history **on by default**. Recording, hosted sharing, cloud accounts, and recurring services are outside v1. Finalized-only history is the working interpretation of the accepted Q6 recommendation with its default changed; the product spec still needs to define exactly when a capture becomes final.

This report independently compares stack choices against that scope rather than treating the earlier Snapzy shortlist as a conclusion. Evidence includes Apple/framework documentation and Snapzy source at commit [`9f48e0304c1aca8a945667b49e9b988958d26e7c`][snap-tree], matching the existing repository evidence snapshot. Public source was fetched read-only. No app was installed, built, launched, benchmarked, or forked for this report. File counts and the existence of tests are evidence of structure, not evidence that tests pass.

## What Snapzy actually uses

| Area | Verified implementation | Implication for this project |
|---|---|---|
| Capture | `ScreenCaptureManager` imports AppKit, CoreGraphics, CoreImage, ImageIO, ScreenCaptureKit; its compatibility wrapper uses `SCScreenshotManager` on macOS 14+ and a single-frame stream fallback on 13. [Source][snap-capture] | Direct access to the relevant macOS primitives. A fresh macOS 14+ baseline could avoid the 13 fallback; an evaluation fork should initially retain upstream behavior. |
| UI | SwiftUI and AppKit coexist; scrolling HUD uses a nonactivating `NSPanel`. [README][snap-readme], [scrolling design][snap-scroll] | This is a native hybrid, not a pure SwiftUI app. The panel approach matches the approved floating-thumbnail interaction. |
| OCR | `VisionOCRProvider` routes to `OCRService`, which uses `VNRecognizeTextRequest`. Optional remote engines also exist. [Provider][snap-ocr-provider], [service][snap-ocr] | Local OCR is available without an inference server. Disable/remove remote paths in v1 rather than relying only on their current defaults. |
| Scrolling | Region-scoped `SCStream`, bounded frame ring, serial background stitching, pixel matching, and `VNTranslationalImageRegistrationRequest` recovery. [Design][snap-scroll], [stitcher][snap-stitch] | This is meaningful reusable engineering. The quality of alignment and failure handling must be measured with real target apps. |
| History | GRDB SQLite metadata, image paths, separate thumbnails, retention service; history preference defaults true. [History][snap-history], [store][snap-history-store], [preference][snap-history-pref] | Default-on matches the user’s correction. Existing retention and deletion semantics need review. |
| Editable sessions | Sidecar contains a manifest, original image data, optional cutout and embedded assets. `AnnotationSessionStore` writes `sessionData.originalImageData` to disk. [Implementation][snap-session], [annotation design][snap-annotate] | Direct mismatch with finalized-only persistence. Hiding the undo UI or flattening only the exported image does not remove the persisted original. |
| Dependencies | Pinned GRDB 7.10.0, Sparkle 2.8.1, Swift-WebP 0.6.1, libwebp-Xcode 1.5.0. [Lockfile][snap-lock] | Dependencies are explicit and finite, but each binary architecture, toolchain requirement, and license still needs verification. No need to replace GRDB merely for novelty. |

The project declares macOS 13 deployment targets; development docs advertise Xcode 15+. Those are source declarations, **not proof** that the currently resolved packages compile using Xcode 15 or that a downloaded release has an Intel slice. The initial build must resolve this. [Project][snap-project], [development instructions][snap-dev]

## Independent comparison

The rankings below are judgments based on the capability boundaries cited here. They do not assert measured RAM, latency, build time, energy, or developer productivity.

| Candidate | Strongest reasons to choose it | Costs and limitations for this scope | Assessment |
|---|---|---|---|
| Swift + AppKit/SwiftUI + Apple capture/image APIs | Native window, focus, pasteboard, drag, capture, and OCR APIs in one language/toolchain; SwiftUI can live inside AppKit and vice versa. [Apple interoperation][apple-ui] | Two UI paradigms require clear state ownership. macOS-specific expertise and Xcode tooling remain necessary. | **Best fit.** Keep capture/editor internals independent of declarative view refreshes. |
| Mostly SwiftUI + native services | Simple settings/library composition; shares Swift types with capture/OCR. Apple explicitly supports bridging to AppKit. [Apple interoperation][apple-ui] | Fine-grained overlay activation, window levels, event handling, and canvas behavior still warrant native bridges for this product. Treating “pure SwiftUI” as a goal can add wrappers without user benefit. | **Viable variation**, not a fundamentally different capture stack. Use where it simplifies actual views. |
| Tauri + Rust + HTML/CSS/TypeScript + native bridges | Rust core with OS-provided WKWebView on macOS; web editor UI may suit a team with existing web code. Tauri’s IPC architecture separates core work and web rendering. [Process model][tauri-process], [architecture][tauri-architecture] | Capture, Vision, specialized panels, permissions, and native dragging need platform integration; this project would maintain Rust/web plus native interfaces. Image buffers crossing IPC need deliberate ownership and lifetime design. | **Second-tier option** if cross-platform support or an existing web editor becomes a real requirement. Neither is approved today. |
| Electron + TypeScript + native bridges | Mature web UI workflow; built-in `desktopCapturer` exposes screen/window sources. [API][electron-capture] | Main/renderer processes and IPC still exist; specialized native UX and Vision need bridges. Chromium/Node-related updates and a carefully constrained renderer are additional maintenance work. [Process model][electron-process], [security guidance][electron-security] | **Not preferred** for a small resident macOS utility. No measured claim that a particular Electron implementation would be too slow. |
| Qt/C++ + Qt Widgets/Quick + Objective-C++ bridges | Native compiled image-processing code and substantial cross-platform GUI support; Qt 6.11 documents macOS 13+ including 26, x86_64 and arm64. [macOS support][qt-mac] | macOS polish/OCR may need Objective-C++ integration; deploy Qt libraries/plugins; audit module licenses. Qt’s frame-stream capture API is not a scrolling-stitch solution. [Capture][qt-capture], [licensing][qt-license] | **Credible when cross-platform or C++ expertise dominates.** No compensating advantage for the present single-platform app. |

No web stack is disqualified from producing a good app. The issue is whether its extra runtime and language boundaries buy something this particular product needs. Here, the hard work is platform interaction and image lifecycle, while the approved UI is relatively small. That favors the native option. A proven reusable web annotation engine or a committed Windows/Linux roadmap would justify reopening this conclusion.

An all-AppKit Swift app is also reasonable: it trades declarative convenience for consistent imperative lifecycle control. A Swift UI with a Rust/C++ stitching library should be considered only after profiling identifies a bottleneck or a vetted library solves a demonstrated problem. Rewriting working Swift pixel code in another language is not inherently an optimization.

## Capture, scrolling, and Intel constraints

`SCScreenshotManager` provides single-image capture with content filtering; it does not itself implement a complete capture/editor/history workflow. [Apple API][apple-screenshot] The owner’s current OS clears Snapzy’s declared minimum, but required APIs, third-party frameworks, and released executables must each support x86_64. Apple documents universal builds containing Intel and Apple silicon slices; an Intel Mac cannot run or debug the arm64 slice. A successful local Intel build therefore proves only that slice. [Universal binaries][apple-universal]

Scrolling remains a difficult subsystem regardless of UI stack. Snapzy’s approach addresses overlap, timing, fixed regions, duplicate frames, and direction changes, with a maximum output height and explicit failure outcomes. It uses native-scale frame normalization, a bounded frame ring, and off-main serial work. Its auto-scroll posts bounded synthetic events and requires Accessibility permission, with manual guidance when denied. [Scrolling design][snap-scroll]

**Recommendation:** Keep manual scrolling functional without making auto-scroll permission a prerequisite for every capture. Evaluate plain text, repeated rows, sticky headers, browser zoom, animation, lazy-loaded content, reverse scrolling, and mixed-DPI displays. Require an explicit recoverable failure when stitching cannot align, rather than silently producing missing or repeated content. These are proposed acceptance cases, not verified Snapzy behavior.

Avoid an Apple-silicon-only OCR/model path. The existing `VNRecognizeTextRequest` path is the candidate for this Intel evaluation; do not conflate it with Apple Intelligence product hardware requirements. Apple provides image-text recognition through Vision, but local accuracy and latency still require measurement. [Apple OCR example][apple-ocr], [Snapzy OCR source][snap-ocr]

## Persistence and redaction

**Recommend keeping GRDB + SQLite if adapting Snapzy.** Use the database for capture identity, timestamps, dimensions, file ownership, retention state, and any future finalized-image OCR index. Keep images in an app-owned local directory and regenerate thumbnails from the authoritative finalized image. GRDB is a SQLite toolkit; SQLite is available on Apple platforms. [GRDB][grdb], [Apple data models][apple-data]

| Approach | When it makes sense | Tradeoff |
|---|---|---|
| SQLite + GRDB | Existing Snapzy foundation; explicit queries, transactions, migrations, inspectable storage | Additional package and schema work; file writes still need coordination with database commits. |
| SwiftData | Fresh native app with straightforward models and a tested migration strategy | Concise Apple-native persistence over Core Data; changing an existing store yields no immediate screenshot benefit. [Apple SwiftData][apple-swiftdata] |
| Core Data | Team already comfortable with its models, migrations, and object lifecycle | Mature platform option; additional mapping/lifecycle complexity may be unnecessary for a compact capture catalog. [Apple data models][apple-data] |
| JSON manifest + files | Throwaway small prototype | Easy to inspect, but concurrency, querying, retention, recovery, and migration become application responsibilities. Not recommended for default-on production history. |

These persistence recommendations are design inferences. None of the choices makes opaque redaction safe automatically.

**Required adaptation experiment:** follow one identifiable synthetic secret from capture through temporary file, thumbnail, editor undo, solid redaction, save/copy/drag, history, OCR metadata, restart, and deletion. Snapzy’s documentation says clear-history removes records, thumbnails, and sidecars while preserving capture files; that should not be presented to users as deleting all captures. [History semantics][snap-history] Its annotation sidecar explicitly preserves original bytes. [Implementation][snap-session]

Proposed invariant: once a redacted result is finalized, every app-owned persistent representation and subsequent export derives from that flattened result. Keep reversible originals only within the active editing session; do not persist editable sessions containing them. Solid redaction must replace pixels at export, not merely hide a removable layer. Review crop bounds, thumbnails, caches, embedded image assets, diagnostic attachments, and stale OCR text too. This is a proposed product/security invariant, not a claim about current upstream compliance.

Default-on history also needs a clear commit boundary: immediately saving raw captures and deleting them after redaction cannot promise that originals were never persisted. An in-memory pending capture can become a finalized unedited capture on a defined action; opening the editor keeps it pending until commit. The exact action for thumbnail dismissal or timeout is an outstanding product decision. No application can retract a capture already pasted elsewhere or promise forensic deletion from external backups merely by deleting its own file.

## Build, maintenance, and distribution

For a native foundation, use Xcode’s toolchain and `xcodebuild` for reproducible builds/tests; the user has selected **Cursor as the IDE**. A terminal agent is not a replacement for SDKs, AppKit runtime testing, Instruments, or the visual debugging needed for overlay geometry. Snapzy documents command-line build/test entry points and a distinct debug bundle identity for privacy permissions. [Development instructions][snap-dev]

**Current build blocker, from the coordinating agent’s local checks this turn:** no Xcode app was found in `/Applications` or `~/Applications`; `xcode-select` points to Command Line Tools, and `xcodebuild` fails because full Xcode is required. This is a missing build toolchain, **not a Snapzy compilation failure**. Desktop Cursor installation does not supply that toolchain. Re-run the build once a compatible full Xcode installation is available; no foundation rejection should be recorded from this environment failure.

Swift gives this scope a shorter integration path, but Snapzy is a broad existing codebase. The capture manager and stitcher alone have substantial implementation surface; dead history UI and unused preferences are explicitly documented upstream. Evaluate module boundaries and required changes instead of treating language choice as a maintainability guarantee. [Capture source][snap-capture], [stitcher][snap-stitch], [history documentation][snap-history]

For later public distribution, Developer ID signing, hardened runtime, and notarization form a separate release concern across stack choices. Apple’s notarization documentation describes the signing requirements; that should not be confused with a requirement to buy a developer membership just to begin every local build. This report has not verified local signing identities or distribution entitlements. [Apple notarization][apple-notarize]

Snapzy’s BSD-3-Clause license permits modified source/binary redistribution subject to its notice/disclaimer and endorsement conditions. Preserve the upstream notices and audit dependency licenses when adopting it. [License][snap-license] Electron itself is MIT; Qt has LGPL/GPL/commercial choices with module-specific differences, so “Qt is free” is insufficient as a distribution policy. [Electron license][electron-license], [Qt licensing][qt-license] These are engineering selection observations, not a completed legal review of a future release.

## Minimum evidence before accepting a foundation

1. **Reproduce an Intel debug build.** Record exact commit, package locks, Xcode/Swift versions, actual deployment target, `file`/`lipo` output, and the build result. Resolve toolchain mismatches before attributing failure to the stack.
2. **Run relevant upstream tests.** Capture geometry, scrolling stitcher, history, annotation exporter/session, and OCR tests are present in the [tree][snap-tree]. Report actual results and permission-dependent exclusions separately.
3. **Exercise the approved capture loop on this Mac.** Region/window/full screen; copy/save/drag/edit; keyboard focus; multiple Spaces and available monitors; permission denial/recovery. User approval of an architecture is not proof these interactions work.
4. **Measure an agreed sample workload.** Capture-to-thumbnail latency, idle CPU/memory, long-scroll peak memory, OCR latency/accuracy, and seams using repeatable fixtures. Set acceptance thresholds with the baseline app/workflow; do not invent benchmark wins.
5. **Prove the history/redaction invariant.** Include a forced quit between rendering, file replacement, thumbnail generation, and database update. Verify retained files and metadata after restart. This is the principal known upstream mismatch.
6. **Verify local-only behavior.** Exercise all v1 actions offline. Inspect optional cloud/OCR/update/diagnostic paths; distinguish an update check from screenshot upload and define allowed behavior explicitly. Do not assume the upstream feature surface disappears when its menu items are hidden.

**Acceptance rule:** adapt Snapzy if it builds/runs on Intel, its approved workflows pass, and finalized-only history plus a narrow local feature surface can be implemented with comprehensible changes. If its coupling makes those changes disproportionately invasive, evaluate a smaller native foundation or a fresh native app before changing languages. Reopen Tauri/Electron/Qt only when evidence or new product requirements outweigh the macOS integration benefit.

This closes the stack research question with a provisional recommendation. It does not close the foundation evaluation, the history commit-boundary decision, or the hands-on performance/usability questions. Those remain inputs to the Pocock specification and evaluation tickets.

[snap-tree]: https://github.com/duongductrong/Snapzy/tree/9f48e0304c1aca8a945667b49e9b988958d26e7c
[snap-project]: https://github.com/duongductrong/Snapzy/blob/9f48e0304c1aca8a945667b49e9b988958d26e7c/Snapzy.xcodeproj/project.pbxproj
[snap-readme]: https://github.com/duongductrong/Snapzy/blob/9f48e0304c1aca8a945667b49e9b988958d26e7c/README.md
[snap-history]: https://github.com/duongductrong/Snapzy/blob/9f48e0304c1aca8a945667b49e9b988958d26e7c/docs/HISTORY.md
[snap-history-store]: https://github.com/duongductrong/Snapzy/blob/9f48e0304c1aca8a945667b49e9b988958d26e7c/Snapzy/Services/History/CaptureHistoryStore.swift
[snap-history-pref]: https://github.com/duongductrong/Snapzy/blob/9f48e0304c1aca8a945667b49e9b988958d26e7c/Snapzy/Services/History/CaptureHistoryPreferences.swift
[snap-capture]: https://github.com/duongductrong/Snapzy/blob/9f48e0304c1aca8a945667b49e9b988958d26e7c/Snapzy/Services/Capture/ScreenCaptureManager.swift
[snap-scroll]: https://github.com/duongductrong/Snapzy/blob/9f48e0304c1aca8a945667b49e9b988958d26e7c/docs/SCROLLING_CAPTURE.md
[snap-stitch]: https://github.com/duongductrong/Snapzy/blob/9f48e0304c1aca8a945667b49e9b988958d26e7c/Snapzy/Services/Capture/ScrollingCapture/ScrollingCaptureStitcher.swift
[snap-ocr]: https://github.com/duongductrong/Snapzy/blob/9f48e0304c1aca8a945667b49e9b988958d26e7c/Snapzy/Services/Media/OCRService.swift
[snap-ocr-provider]: https://github.com/duongductrong/Snapzy/blob/9f48e0304c1aca8a945667b49e9b988958d26e7c/Snapzy/Services/Media/OCR/VisionOCRProvider.swift
[snap-annotate]: https://github.com/duongductrong/Snapzy/blob/9f48e0304c1aca8a945667b49e9b988958d26e7c/docs/ANNOTATE.md
[snap-session]: https://github.com/duongductrong/Snapzy/blob/9f48e0304c1aca8a945667b49e9b988958d26e7c/Snapzy/Features/Annotate/Services/AnnotationSessionStore.swift
[snap-lock]: https://github.com/duongductrong/Snapzy/blob/9f48e0304c1aca8a945667b49e9b988958d26e7c/Snapzy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
[snap-dev]: https://github.com/duongductrong/Snapzy/blob/9f48e0304c1aca8a945667b49e9b988958d26e7c/docs/DEVELOPMENT.md
[snap-license]: https://github.com/duongductrong/Snapzy/blob/9f48e0304c1aca8a945667b49e9b988958d26e7c/LICENSE
[apple-ui]: https://developer.apple.com/videos/play/wwdc2022/10075/
[apple-screenshot]: https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager
[apple-ocr]: https://developer.apple.com/documentation/vision/locating-and-displaying-recognized-text
[apple-universal]: https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary
[apple-data]: https://developer.apple.com/documentation/technologyoverviews/structured-data-models
[apple-swiftdata]: https://developer.apple.com/documentation/swiftdata/
[apple-notarize]: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
[tauri-process]: https://tauri.app/concept/process-model/
[tauri-architecture]: https://tauri.app/concept/architecture/
[electron-capture]: https://www.electronjs.org/docs/latest/api/desktop-capturer
[electron-process]: https://www.electronjs.org/docs/latest/tutorial/process-model
[electron-security]: https://www.electronjs.org/docs/latest/tutorial/security
[electron-license]: https://github.com/electron/electron/blob/main/LICENSE
[qt-mac]: https://doc.qt.io/qt-6/macos.html
[qt-capture]: https://doc.qt.io/qt-6/qscreencapture.html
[qt-license]: https://doc.qt.io/qt-6/licensing.html
[grdb]: https://github.com/groue/GRDB.swift
