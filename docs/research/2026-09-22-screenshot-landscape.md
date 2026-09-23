# Screenshot-app: CleanShot, alternatives, and macOS source projects

Researched 22 September 2026. Status: research, not an accepted product specification or architecture decision.

## Recommendation

**Evaluate Snapzy and MacShot before implementing a replacement.** Snapzy is the strongest broad candidate to adopt or extend: native Swift, a CleanShot-like capture/annotation/history workflow, recent releases, and a declared BSD-3-Clause license. MacShot is a strong alternative for fast selection-and-annotation, under GPLv3. For a smaller screenshot-focused foundation, examine capcap; for individual capabilities, examine ScrollSnap and TRex. These are research judgments based on documentation and source metadata, not hands-on quality rankings. [Snapzy](https://github.com/duongductrong/Snapzy), [MacShot](https://github.com/sw33tLie/macshot), [capcap](https://github.com/realskyrin/capcap).

The useful product target is **capture → explain/redact → copy or drag into another app**, with local history and OCR. Reproducing CleanShot's recording studio and hosted collaboration would make this a much larger project. The user likes CleanShot and wants to avoid paying; no particular subset of features has yet been identified as indispensable.

Important findings:

- CleanShot now sells Basic for **$35 once**, including one year of updates and 1 GB cloud storage. Update renewal is optional at $19/year; Pro is $10/user/month billed annually. Both include the full desktop app. If the user already owns a perpetual license, avoiding renewal may be sufficient; the user's current entitlement has not been inspected. [Current pricing](https://cleanshot.com/pricing).
- CleanShot **5.0**, released 1 September 2026, added Studio Mode. The latest listed release is **5.0.1**, dated 18 September. Older comparisons miss a substantial video-editing expansion. [Changelog](https://cleanshot.com/changelog).
- The most popular repository is not necessarily the best Mac choice. Flameshot has substantial adoption, but its Homebrew cask is disabled and users report a broken Intel v14 binary. [Homebrew cask](https://github.com/Homebrew/homebrew-cask/blob/main/Casks/f/flameshot.rb), [upstream release discussion](https://github.com/flameshot-org/flameshot/discussions/4750).
- Source visibility does not imply a permissive license: Capso is BSL 1.1; BetterShot's original code is BSD, but the combined application includes AGPL/GPL adaptations. See the licensing section below.

## Evidence and coverage

Sources: official vendor feature/pricing/help/release pages; public GitHub API metadata; repository READMEs, licenses, selected build configurations, and Apple documentation. GitHub discovery used four searches sorted by stars, then direct lookups for established candidates missed by search. We inspected 18 accessible repositories, plus one unavailable candidate. This is a relevant shortlist, not a claim to have ranked every repository on GitHub or measured market share.

The CleanShot inventory covers all feature families and documented subfeatures found across its public feature pages, API reference, and changelog. It is not an audit of every preference in the installed app. Applications were not installed or benchmarked, and downloaded binaries were not executed or architecture-inspected. A feature absent from a vendor page is **unverified**, not proven absent.

Local compatibility was checked directly: `uname -m` returned `x86_64`; `sw_vers` returned macOS `26.7`, build `25G229`. Therefore Intel support matters even when the OS minimum is satisfied. Do not confuse a macOS minimum, a release filename, source build settings, and a tested working Intel binary.

## CleanShot capability inventory

### Capture and precision

| Family | Documented capabilities | Evidence |
| --- | --- | --- |
| Capture targets | Area, window, full screen, timed capture, and scrolling content | [Features](https://cleanshot.com/features) |
| Unified capture | One shortcut opens All-In-One; specify dimensions, lock proportions, reuse the last selection | [Screenshots](https://cleanshot.com/screenshots) |
| Precision | Crosshair, magnification, frozen-screen selection | [Features](https://cleanshot.com/features) |
| Window presentation | Transparent output; optional shadow; wallpaper, custom-image, or solid backgrounds; padding | [Features](https://cleanshot.com/features) |
| Long content | Vertical and horizontal scrolling; automatic scrolling; intended for pages, conversations, documents, and code | [Changelog](https://cleanshot.com/changelog), [API](https://cleanshot.com/docs-api) |
| Desktop cleanup | Hide desktop icons and widgets; crop the notch from fullscreen-app captures | [Homepage](https://cleanshot.com/), [Changelog](https://cleanshot.com/changelog) |

“Works in every app” is the vendor's claim, not a verified guarantee about virtualized lists, animations, or fixed headers. A replacement should have explicit scrolling failure detection.

### Annotation, redaction, and image presentation

| Family | Documented capabilities | Evidence |
| --- | --- | --- |
| Markup | Arrows including curves, lines, rectangles, filled rectangles, ellipses, text, pencil, counters, spotlight, smart highlighter | [Features](https://cleanshot.com/features) |
| Tool detail | Four arrow styles; seven text presets; smoothed pencil; text-aware highlighter sizing | [Features](https://cleanshot.com/features) |
| Concealment | Blur, pixelation, solid redaction; secure/smooth blur choices and randomized pixelation | [Screenshots](https://cleanshot.com/screenshots), [Features](https://cleanshot.com/features) |
| Geometry | Crop and resize; ratio/edge snapping; rotate and flip | [Screenshots](https://cleanshot.com/screenshots), [Changelog](https://cleanshot.com/changelog) |
| Composition | Drag multiple images onto one canvas; position them; save editable CleanShot projects | [Features](https://cleanshot.com/features) |
| Backgrounds | Twenty included backgrounds, custom images, padding, shadows, alignment, output ratios, reusable presets, automatic content balancing | [Screenshots](https://cleanshot.com/screenshots) |
| Editing conveniences | Color sampling/saved colors, automatic preset application, object duplication/copy/paste, undo/redo, constrained movement | [Changelog](https://cleanshot.com/changelog) |
| Formats and color | PNG/JPEG workflows; WebP/HEIC support; optional sRGB conversion; multipage printing for long captures | [API](https://cleanshot.com/docs-api), [Changelog](https://cleanshot.com/changelog) |

For our app, keep editable local documents separate from flattened share exports. Solid redaction must replace exported pixels; storing hidden text or originals inside a shared project defeats that purpose. This is a proposed acceptance requirement, not a claim that a competitor has passed such a test.

### Overlay, references, OCR, and history

| Family | Documented capabilities | Evidence |
| --- | --- | --- |
| Post-capture overlay | Copy, save, annotate, drag into other apps; file details; restore dismissed overlay | [Features](https://cleanshot.com/features), [Homepage](https://cleanshot.com/) |
| Overlay controls | Position, size, auto-dismiss, multiple displays, swipe gestures, temporary hiding | [Features](https://cleanshot.com/features) |
| Pinned references | Always-on-top images; scaling, transparency, arrow-key positioning, click-through lock | [Features](https://cleanshot.com/features) |
| Text extraction | On-device OCR; image/region input; clipboard output; QR decoding; 30+ languages; automatic language detection | [Features](https://cleanshot.com/features), [Changelog](https://cleanshot.com/changelog) |
| OCR control | Retain or remove line breaks through the automation API | [API](https://cleanshot.com/docs-api) |
| Recent captures | Restore, copy, share, delete, filter by capture type; history retention up to one month | [Screenshots](https://cleanshot.com/screenshots) |
| Further conveniences | Hide/close pinned images; reopen imported files in history; Option-copy without closing the editor | [Changelog](https://cleanshot.com/changelog) |

### Recording and Studio Mode

| Family | Documented capabilities | Evidence |
| --- | --- | --- |
| Recording inputs | Display, window, or area; microphone, system sound, and camera | [Features](https://cleanshot.com/features), [Recording](https://cleanshot.com/screen-recording) |
| Output controls | H.264 MP4 or GIF; quality, frame-rate, and resolution controls | [Features](https://cleanshot.com/features) |
| Presentation | Cursor visibility; click styling/animation; keystroke positioning/sizing/theme/filtering; camera placement, sizing, shape, fullscreen | [Features](https://cleanshot.com/features) |
| Recording workflow | Countdown, pause/resume, elapsed time, desktop cleanup, Do Not Disturb, movable controls, audio indicator, muted-mic warning, mono audio | [Changelog](https://cleanshot.com/changelog), [Features](https://cleanshot.com/features) |
| Studio editing | Trimming, cursor-following zooms, cursor smoothing, cursor appearance/click effects, motion blur | [Recording](https://cleanshot.com/screen-recording) |
| Video presentation | Background, padding, shadows, landscape/square/portrait output, hardware-accelerated rendering | [Recording](https://cleanshot.com/screen-recording) |
| Post-recording adjustments | Cursor, keystroke, and camera customization; new video editor and redesigned settings | [Changelog](https://cleanshot.com/changelog) |

### Cloud and collaboration

Optional cloud capabilities include one-click uploads and links, 4K media, searchable transcripts/captions, screenshot-content and tag search, image and timestamped video comments, passwords, expiration, access control, custom domains/branding, team administration, SSO, and SCIM. The site advertises ISO 27001 certification. These are service capabilities; do not imply they are all local desktop functions. [Cloud product](https://cleanshot.com/product/cloud), [Features](https://cleanshot.com/features).

Basic includes 1 GB storage; Pro adds unlimited storage subject to fair use, branding, access/security controls, and team features. Cloud use is optional for the desktop application. Some plan-table checkmarks do not survive text extraction, so fine-grained cloud entitlements should be rechecked visually if they become selection criteria. [Pricing](https://cleanshot.com/pricing), [FAQ](https://cleanshot.com/faq).

### Automation and customization

CleanShot's URL scheme exposes All-In-One; area/previous-area/fullscreen/window/timed/scrolling capture; pin; recording; text recognition; open file/clipboard in Annotate; desktop-icon visibility; overlay insertion; history/restore; and settings. Relevant parameters include display, region coordinates, post-capture action, auto-scroll/start, input file, and OCR line-break handling. [API reference](https://cleanshot.com/docs-api).

Custom shortcuts, post-capture behavior, formats, and sharing settings are public product features. Raycast integration includes sending captures to AI Chat. [Homepage](https://cleanshot.com/), [Changelog](https://cleanshot.com/changelog).

## Alternative applications

Selection emphasizes workflow relevance, free-use conditions, native integration, active evidence, and a usable Intel path. “Local” describes the core workflow; optional upload/AI features can change where content goes. Prices are observed offers, not purchases or guarantees.

| App | Why compare it | Cost/free-use boundary | Mac / evidence limits |
| --- | --- | --- | --- |
| **macOS Screenshot + Markup/Preview** | Baseline: region/window/display, timer, clipboard, floating thumbnail, quick editing | Included with macOS | Native on this Mac; advanced history/stitching/editor workflow not established by this page. [Apple](https://support.apple.com/en-us/102646) |
| **Shottr** | Scrolling, OCR/QR, pinning, pixel measurement, color tools, compositing, backgrounds, S3 upload | Personal free use with reminders after 30 days; $12 Basic or $30 Friends one-time; license required commercially | macOS 10.15+ documented; v1.9.2 dated 17 Sep 2026; current Intel binary not inspected. Telemetry has an opt-out. [Features/FAQ](https://shottr.cc/), [purchase](https://shottr.cc/purchase.html) |
| **Snipaste** | Excellent pin/reference workflow: translucent, rotatable, click-through images, selection precision | Personal use free; version 2 business use paid; Pro $8.99/one device or $19.99/three | Official universal Mac download. Not a verified source-code foundation. [Official site](https://www.snipaste.com/) |
| **Xnapper** | Fast visual polish: balancing, backgrounds, automated sensitive-data concealment, OCR, presets/history | Free exports carry watermark; localized official pricing lists Basic $29.99 once, one Mac, one year of updates | Native Mac; Intel binary unverified. Mac homepage marks cloud “coming soon”; Web changelog records cloud shipped Dec 2024. Keep those products separate. [Site](https://xnapper.com/), [pricing](https://xnapper.com/es/pricing), [changelog](https://xnapper.com/changelog) |
| **Snagit** | Documentation-heavy editor, scrolling, text extraction, simplified graphics, searchable library, recording | Subscription, no permanent free tier; retrieved store showed €39.56/year, localized rather than a verified US quote | Dedicated requirements page lists macOS 15/26/27, while store says 14+. Use the stricter current requirements pending version confirmation. Platform-specific features vary. [Product](https://www.techsmith.com/snagit/), [store](https://www.techsmith.com/store/snagit), [requirements](https://www.techsmith.com/snagit/system-requirements/) |
| **Zight** | Links, feedback, team sharing, recording/GIF and cloud workflow | Free Share tier; Create $9.95/user/month annually; Collaborate $12 annually with team minimum | Mac app available; account/cloud oriented, paid upgrades do not meet zero-cost intent. [Plan comparison](https://zight.com/pricing) |
| **Monosnap** | Screenshot annotation plus hosted/external-storage sharing and recordings | Official indexed table: personal free, 2 GB, five-minute video; $2.50 non-commercial/$5 commercial monthly equivalents | Current site redirects to monosnap.ai and renders poorly here. Treat indexed prices as provisional; architecture unverified. [Indexed official plan page](https://monosnap.com/pay) |
| **Flameshot** | Mature open-source inline annotation and CLI | Free, GPLv3 | Qt/C++; Mac packaging/Gatekeeper and Intel v14 reports make it a reference rather than first install recommendation. [Product](https://flameshot.org/), [cask](https://formulae.brew.sh/cask/flameshot) |
| **ksnip** | Cross-platform editor with extensive annotations and output integrations | Free, GPLv3 | Qt/C++; macOS supported, but old stable release and documented scaling problems deserve testing. [Repository](https://github.com/ksnip/ksnip) |
| **Snapzy** | Broad native replacement: annotations, scroll/OCR, overlay, editable history, video/GIF and optional own-storage sharing | Free; BSD-3-Clause declared | macOS 13+; active source/release documentation. Use local Vision OCR rather than optional external model endpoints. [Repository](https://github.com/duongductrong/Snapzy) |
| **MacShot — sw33tLie** | Frozen-screen annotation, scrolling, redaction, history, pinning, recording | Free; GPLv3 | macOS 12.3+; current README describes more features than the July stable release may contain. [Repository](https://github.com/sw33tLie/macshot) |
| **capcap** | Smaller native capture/annotate/scroll/pin/history workflow | Free; MIT | macOS 14+, universal according to README. Optional upload credentials are documented as stored in UserDefaults; review that design before reuse. [English README](https://github.com/realskyrin/capcap/blob/main/README.en.md) |
| **SimplShot** | Screenshot/PDF annotation, OCR, backgrounds/templates, batch window capture | Advertised fully free, no account, local processing | macOS 14+; vendor claims open source but GitHub destination failed to fetch in this pass; source/license and Intel distribution remain unverified. [Official site](https://simplshot.com/) |
| **Screen Studio** | Adjacent benchmark for zooms, smooth cursor, camera/audio, transcription and video polish | Commercial; current amount not verified in extracted page | Recording/editor product. Official guide lists Ventura 13.1+, Intel MacBook Pro 2018+/Air 2020+; actual performance untested. [Official site](https://screen.studio/), [requirements](https://screen.studio/guide/system-requirements) |

Other source-based contenders—BetterShot, Screendrop, Capso—are covered below. Kap, QuickRecorder, and Cap are recording references. ShareX is explicitly a Windows product, so its popularity does not make it a Mac implementation candidate. Greenshot's public downloads primarily describe its Windows project; its paid Mac offering should not be equated with a free native source base. [ShareX](https://getsharex.com/), [Greenshot downloads](https://getgreenshot.org/downloads/).

## GitHub comparison

Exact snapshot metadata and release links are in [github-repositories.md](github-repositories.md). All 18 accessible repositories were unarchived when queried. “Last commit” there means the latest default-branch commit, which may be documentation, translations, dependency maintenance, or release automation. It is not proof of recent feature work. Popularity and open-issue counts alone are not quality scores.

| Repository | Role and useful material | Foundation assessment |
| --- | --- | --- |
| [Snapzy](https://github.com/duongductrong/Snapzy) | Native SwiftUI/AppKit/ScreenCaptureKit; capture, annotation, history, local redaction, recording, URL actions; extensive feature and development docs | **First broad foundation to evaluate.** BSD-3-Clause; documented macOS 13+/Xcode 15+ baseline, dedicated tests. Some newer feature requirements vary. |
| [MacShot](https://github.com/sw33tLie/macshot) | Native Swift/AppKit; direct annotation, Vision-based stitching, multiple export formats, editable history, OCR, recording | **First free-app comparison alongside Snapzy.** GPLv3; macOS 12.3 deployment target. Evaluate release versus newer main-branch behavior. |
| [capcap](https://github.com/realskyrin/capcap) | AppKit capture/editor, scrolling, pins, OCR/history; MIT, universal macOS 14+ | **Smaller screenshot-oriented foundation.** Inspect optional credential storage and actually test mixed-display capture. |
| [BetterShot](https://github.com/KartikLabhshetwar/better-shot) | SwiftUI/AppKit; capture shelf, extensive shortcuts, automation, video studio and optional Cloudflare sharing | Current x86_64 release exists; macOS/Xcode 26+ required. Mixed licensing and expanded video/notch scope make it less straightforward to reuse wholesale. |
| [Screendrop](https://github.com/fayazara/Screendrop) | Native capture, annotation studio, library, recording studio, optional self-hosted sharing | CC0 declaration; macOS 26.4+ minimum. Interesting broad reference, but much larger than a screenshot MVP; Intel binary not established by generic DMG name. |
| [Capso](https://github.com/lzhgus/Capso) | Swift 6, SwiftUI/AppKit, modular SPM packages for capture, annotation, OCR, recording/history | Good architecture reference. macOS 15+/Xcode 16+/XcodeGen. Universal build checks exist. **BSL, not unrestricted permissive reuse.** |
| [Flameshot](https://github.com/flameshot-org/flameshot) | C++/Qt capture overlay, annotation tools, CLI, mature cross-platform community | Largest direct screenshot project in this sample, but Mac packaging issues reduce immediate suitability here. GPLv3. |
| [eSearch](https://github.com/xushengfeng/eSearch) | TypeScript/Electron; OCR, search/translation, pinning, scrolling and recording | Broad cross-platform feature reference; current darwin-x64 assets exist. GPLv3. Larger runtime than a native utility is a tradeoff, not a measured performance verdict. |
| [ksnip](https://github.com/ksnip/ksnip) | Qt capture/editor, annotation dependencies, integrations | Useful editor behavior reference. Stable release dates to 2023 despite 2026 commits; source-build dependency work and Mac scaling issues. GPLv3. |
| [ScrollSnap](https://github.com/Brkgng/ScrollSnap) | Swift/AppKit/ScreenCaptureKit scrolling region capture, stitching, preview/output | **Focused scrolling reference**, MIT; Xcode project and free release ZIP. No claim of a complete CleanShot editor. |
| [TRex](https://github.com/amebalabs/TRex) | Swift menu-bar OCR and CLI | **Focused OCR reference**, MIT; README supports macOS 11+. Inspect architecture and language behavior before embedding. |
| [QuickRecorder](https://github.com/lihaoyun6/QuickRecorder) | Swift recording, audio, windows/apps, camera/presenter overlay | Later recording reference, AGPLv3; macOS 12.3+. June 2025 release fixed an Intel crash but warned of impending certificate expiry; current signing was not tested. |
| [Kap](https://github.com/wulkano/Kap) | Electron recording and export/plugin ecosystem | MIT, Intel release available; latest stable 2022 and default-branch commit 2024 make it a legacy reference. |
| [Cap](https://github.com/CapSoftware/Cap) | Rust/Tauri/TypeScript recording, renderer, sharing and self-hosted service stack | Powerful video reference; AGPLv3 except designated MIT capture/camera crate families and third-party licenses. Too much infrastructure for the proposed first version. |
| [XCap](https://github.com/nashaofu/xcap) | Rust cross-platform capture library | Apache-2.0; useful if choosing Rust/Tauri. Library, not an annotation application; recording described as work in progress. |
| [SnapX](https://github.com/SnapXL/SnapX) | C# cross-platform ShareX-derived workflow | Early-access rewrite explicitly calls capture/upload experimental; no latest stable release returned. Not the low-risk first foundation. GPLv3. |
| [Snappilot](https://github.com/shipiit/snappilot) | Small Swift capture/annotation/OCR/recording contender | Two stars in snapshot; API found no license. Do not infer reuse rights from its description. |
| [Reticle](https://github.com/croc100/Reticle) | Small Swift capture/annotation/upload contender | Five stars; API license unresolved. Lower-confidence candidate than the shortlist. |

`jaywcjlove/shotcat` returned 404 in direct API lookup; it is not represented as a verified repository. Multiple unrelated apps use the name MacShot: the shortlisted project is specifically **sw33tLie/macshot**, not Hunter-Matata/macshot or another similarly named app.

### Licenses that alter the decision

- **Snapzy:** the actual license file is BSD-3-Clause. It permits modification/redistribution subject to its stated conditions. This is a promising starting point; dependency licenses still need checking before distribution. [License](https://github.com/duongductrong/Snapzy/blob/master/LICENSE).
- **Capso:** BSL 1.1 explicitly excludes a commercial third-party screen-capture product/service from its additional-use grant; personal/internal and non-commercial distribution are permitted by the text. The inspected license specifies conversion to Apache-2.0 on **2029-04-08**. Do not summarize this simply as MIT or unrestricted open source. [License](https://github.com/lzhgus/Capso/blob/main/LICENSE).
- **BetterShot:** BSD covers original portions, while its notices identify AGPL-3.0 Cap adaptations and GPLv3 Boring Notch adaptations. The notice says the combined app incorporating the Cap portions must be conveyed under AGPLv3 terms. [License](https://github.com/KartikLabhshetwar/better-shot/blob/main/LICENSE), [component notices](https://github.com/KartikLabhshetwar/better-shot/blob/main/Resources/Licenses/NOTICE.md).
- **Cap:** the root license distinguishes MIT `cap-camera*`/`scap-*` crates from AGPLv3 remainder and third-party components. Check the precise module before reuse. [License](https://github.com/CapSoftware/Cap/blob/main/LICENSE).

These are source-license findings, not a completed dependency or distribution audit.

## Proposed build/adopt decision

| Option | When it makes sense | Next evidence needed |
| --- | --- | --- |
| Keep an already-owned CleanShot version | Only recurring upgrade cost is the problem | Confirm existing license type; no account inspection was performed |
| Adopt an existing free app | The goal is simply replacing the daily workflow | Test Snapzy and MacShot against the same actual tasks |
| Extend a native project | An existing app is close, but a few workflow gaps matter | Build Snapzy/capcap locally; inspect specific modules, dependencies and tests |
| Build a focused app | Learning/ownership or a distinctive workflow justifies maintenance | Decide the indispensable capture/editor actions and create a small technical prototype |

My recommendation is **an evaluation-first path, with Snapzy as the broad candidate and capcap as the smaller codebase candidate**. Preserve screenshot-app as the project workspace; do not import or fork another codebase until that decision is made.

### Screenshot-first scope proposal

1. Region, window, fullscreen and repeat-region capture; configurable global shortcut; reliable cancel and screen-permission guidance.
2. Immediate overlay with copy, save, annotate and drag; no account or network required.
3. Editable arrows, rectangles, text, numbered steps, highlighting, crop; undo/redo; solid redaction with flattened exports.
4. PNG/JPEG export with explicit Retina scaling and color handling.
5. Local OCR to clipboard, pin/reference windows, bounded local history and clear deletion controls.
6. After this works: scrolling capture, image composition, background presets, richer search and URL/Shortcuts automation.
7. Later only if required: GIF/video, microphone/system sound, camera and trimming. Treat Studio-style rendering and cloud collaboration as separate projects in scope and cost.

This ordering is proposed, not agreed. If scrolling or recording is central to the user's existing workflow, promote it rather than claiming a screenshot-only app replaces CleanShot.

### Technical direction and acceptance gates

**Proposed stack:** Swift with AppKit for the status item, overlays, focus and floating windows; SwiftUI where it simplifies settings/library UI; ScreenCaptureKit for capture and future recording; Vision for local OCR; Core Graphics/Core Image for rendering/export. A macOS 14+ baseline is a reasonable candidate to simplify screenshot APIs while retaining Intel support; validate against the installed SDK before committing. Apple documents filtered single-image capture through `SCScreenshotManager`, and Vision text recognition. [Capture API](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage%28contentfilter%3Aconfiguration%3Acompletionhandler%3A%29), [Vision](https://developer.apple.com/documentation/vision/recognizing-text-in-images).

The difficult work is reliability and interaction rather than obtaining pixels. Evaluate:

- Mixed Retina/non-Retina displays, negative coordinates, window shadows/transparency, display changes, fullscreen Spaces and focus restoration.
- Capturing menus/popovers without dismissing them; excluding the app's own overlays from captures.
- Clipboard format and file lifetime when another app receives a drag; repeated captures while previews remain open.
- Redaction export correctness, undo boundaries, and original/editable-image retention in history.
- Scrolling overlap detection, sticky headers, repeated content, reverse scrolling, animations, memory bounds and an explicit failed-stitch result.
- OCR language accuracy on actual material; do not promise all Apple Vision features behave identically on Intel.
- Cold and warm capture latency, idle CPU/memory, energy impact, cleanup, and permission revocation/recovery.
- Actual release binary architecture and clean-machine launch/signing behavior. An Intel filename alone failed as evidence for Flameshot.

No implementation, installation, paid service, cloud deployment, commits, or pushes were performed for this research.

## Independent review

The same comprehensive brief was delegated to a detached **Grok 4.7, high-effort** process after the requested Claude attempt failed and the user changed the model. It completed successfully after 42 tool calls. The CLI was launched with `--model grok-4.7 --reasoning-effort high`; its final usage event identifies the served model as `grok-4.7-build`. See the [independent report](2026-09-22-grok-independent-report.md) and [combined assessment and corrections](2026-09-22-cross-review.md). Agreement between two models is not independent primary evidence.
