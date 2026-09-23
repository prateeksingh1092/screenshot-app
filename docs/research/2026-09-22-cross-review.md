# Combined assessment: Codex research versus Grok's final report

22 September 2026. This is the final synthesis after reading Grok's completed report and rechecking material differences against primary sources.

## Decision

**Evaluate Snapzy and MacShot as working replacements; study Snapzy first if we want to extend an existing codebase. Study capcap if we want a narrower screenshot application.** Use ScrollSnap and TRex as focused implementation references. Build a new app only around a concrete workflow gap discovered in that evaluation, or an explicit desire to own and develop the product.

This differs from Grok's final recommendation, which put MacShot first and did not evaluate Snapzy or capcap. The larger candidate set, source-license inspection, and development documentation support keeping Snapzy first for a broad foundation. This remains an evidence-based shortlist, not a hands-on winner. [Snapzy](https://github.com/duongductrong/Snapzy), [MacShot](https://github.com/sw33tLie/macshot), [capcap](https://github.com/realskyrin/capcap).

| Purpose | Final shortlist | Why |
| --- | --- | --- |
| Replace CleanShot at no software cost | Snapzy, MacShot | Both document the central native capture/edit/OCR/history flow |
| Extend a broad existing app | Snapzy | BSD-3-Clause original project, active releases, feature docs and dedicated tests |
| Build a more focused screenshot utility | capcap | MIT, AppKit, compact capture/editor workflow; inspect upload credential storage before reuse |
| Learn stitching and OCR separately | ScrollSnap; TRex | Focused native projects with MIT licenses |
| Learn recording later | QuickRecorder; Cap | Relevant implementations, but age/licensing/complexity make them secondary references |

Sources for the module shortlist: [ScrollSnap](https://github.com/Brkgng/ScrollSnap), [TRex](https://github.com/amebalabs/TRex), [QuickRecorder](https://github.com/lihaoyun6/QuickRecorder), [Cap](https://github.com/CapSoftware/Cap).

## Where the two reports agree

1. CleanShot 5.0 substantially expands video editing; trying to reproduce the full product in the first milestone is unnecessary scope.
2. The current Basic offer is a perpetual $35 purchase with optional update renewal, so “no more recurring payment” and “no purchase at all” are different requirements.
3. An Intel-compatible native app with local processing is the most relevant technical direction if we build.
4. Capture-to-clipboard, annotations, sound export/redaction behavior and local history matter more than cloud infrastructure for the stated goal.
5. GitHub stars cannot establish performance, release quality, or compatibility; neither report tested apps.

The factual product points are supported by [CleanShot pricing](https://cleanshot.com/pricing) and [release notes](https://cleanshot.com/changelog). The scope/architecture points are our recommendations, not facts established by model agreement.

## Material differences and their resolution

| Topic | Independent Grok outcome | My investigation / resolution | Effect on recommendation |
| --- | --- | --- | --- |
| Candidate coverage | MacShot was the leading native choice; Snapzy, capcap, BetterShot and Screendrop were absent | Direct GitHub lookups established all four as real, currently active candidates; compared READMEs, releases and licenses | **Broadened shortlist; Snapzy leads the foundation evaluation** |
| Flameshot Intel release | Intel-labeled v14 DMG reported as ARM-only; Homebrew disabled | Confirmed upstream user reports and cask `disable!` for Gatekeeper. Did not inspect the binary personally. [Discussion](https://github.com/flameshot-org/flameshot/discussions/4750), [cask](https://github.com/Homebrew/homebrew-cask/blob/main/Casks/f/flameshot.rb) | **Downgraded from likely free option to interaction/code reference** |
| Xnapper cloud | Grok reported cloud/link sharing added in December 2024; my initial page read said coming soon | Changelog explicitly labels this **Xnapper Web**. Mac homepage still marks upload coming soon. Both source statements can coexist. [Changelog](https://xnapper.com/changelog), [Mac homepage](https://xnapper.com/) | Do not grant the Mac application an unverified feature |
| Xnapper price | Grok found $29.99 Basic on a localized official page | Opened that page and confirmed its displayed USD amount, perpetual use and one year of updates. [Pricing](https://xnapper.com/es/pricing) | Filled a gap in my original comparison |
| Capso license | Correctly identified BSL, then overgeneralized it as effectively ideas-only | Actual license permits personal/internal use and non-commercial distribution; restricts a commercial competing screen-capture service. Change date is 2029-04-08. [License](https://github.com/lzhgus/Capso/blob/main/LICENSE) | Free personal use is viable; a future product fork needs deliberate license choice |
| Cap license | GitHub NOASSERTION left license unresolved | Read actual root license: AGPLv3 generally, designated MIT capture/camera crates, third-party exceptions. [License](https://github.com/CapSoftware/Cap/blob/main/LICENSE) | Module-level reuse can be evaluated; do not treat the whole project as MIT |
| BetterShot license | Not covered | Original BSD code plus AGPL Cap and GPL Boring Notch adaptations; repository notice explicitly addresses combined distribution. [Notices](https://github.com/KartikLabhshetwar/better-shot/blob/main/Resources/Licenses/NOTICE.md) | Attractive functionality, more complex reuse than badge suggests |
| Screen Studio Intel support | Official guide lists supported Intel model ranges | Confirmed MacBook Pro 2018+/Air 2020+, macOS 13.1+. [Requirements](https://screen.studio/guide/system-requirements) | Intel support is documented; remains a commercial recording benchmark |
| Snagit OS minimum | Dedicated requirements list macOS 15, 26 and 27 | Confirmed; store still says macOS 14+. Use version-specific stricter requirements instead of merging them. [Requirements](https://www.techsmith.com/snagit/system-requirements/), [store](https://www.techsmith.com/store/snagit) | Compatibility is conditional; irrelevant as a zero-cost winner |
| QuickRecorder maintenance | Older release, Intel fix and expired-certificate warning | Release 1.6.9 confirms Intel crash fix and a future June 14 certificate-expiry warning; API shows no newer stable release. This does not establish the current downloaded app's signature. [Release](https://github.com/lihaoyun6/QuickRecorder/releases/tag/1.6.9) | Keep as a later recording reference; no blind install recommendation |
| Smaller repos | SwiftShot shortlisted; ScreenCap rejected partly because repo is tiny; scap license unresolved | These repositories exist, but size/star counts do not prove implementation quality. Their feature/build completeness was not audited here. [SwiftShot](https://github.com/Amitdvl/SwiftShot), [ScreenCap](https://github.com/8tp/ScreenCap), [scap](https://github.com/jaywcjlove/scap) | Retain as discovery leads, below better-documented native candidates |
| Intel evidence | eSearch described as runnable because x64 asset exists | Asset names establish a published architecture claim, not successful launch. The Flameshot finding demonstrates why | Require a binary/run test for every adoption finalist |

## Claims not promoted into the final recommendation

- Grok's precise “multi-year” development estimate is unsupported. We can establish broad scope and difficult subsystems, not a timeline before requirements and implementation assessment.
- Grok leaned on secondary sources for some Snagit/Screen Studio prices and versions. The synthesis uses official observed values or marks them unknown.
- Grok's hardware-generation and future-macOS discussion was not needed to choose candidates. The parent verified the machine's actual `x86_64` architecture and current OS; no future OS compatibility commitment is made.
- Broad statements that a certificate is mandatory for every local build, that all scrolling capture necessarily needs one permission type, or that ordinary blur is sufficient protection are not accepted as implementation requirements. Those depend on the chosen APIs, build/distribution route and threat model.
- The claimed CleanShot cloud subprocessor detail was not independently readable from the retrieved page. It is unnecessary to the conclusion: uploaded recordings already leave the device by definition; local OCR and hosted transcription remain distinct.
- A missing or unidentified license is a reason to resolve rights before copying, not a basis for improvising a legal conclusion. Similarly, permissive top-level licensing does not clear every dependency.

## What changed after the independent review

Grok materially improved the research by exposing the Flameshot packaging issue, finding official Xnapper pricing, and locating more specific Screen Studio/Snagit requirements. I updated the landscape report with those findings. My broader GitHub search corrected its incomplete native shortlist; actual license files resolved Cap and narrowed its Capso interpretation. The Xnapper disagreement revealed a desktop-versus-web distinction, not a simple true/false conflict.

The final direction is therefore **adopt/evaluate first, then extend a native app or build a focused tool around verified gaps**. If building is the desired outcome regardless of available alternatives, begin with an original capture/edit/export flow and use the shortlist as architectural references. Do not make video studio, hosting, AI services or accounts default requirements.

## Scope questions left open

Research cannot determine which features the user personally relies on. Before implementation, establish: the three most-used CleanShot actions; whether scrolling/recording/share-links are essential; whether use includes work/commercial contexts; and whether history should retain unredacted originals. These are product decisions, not blockers to completing this research.

## Deliverables and delegation evidence

- [Main landscape and complete public-feature inventory](2026-09-22-screenshot-landscape.md)
- [GitHub snapshot: 18 accessible repositories](github-repositories.md)
- [Grok's original final report](2026-09-22-grok-independent-report.md) — preserved as independent output; use this cross-review for corrected conclusions
- [Elaborate delegation brief](../../.scratch/research/grok-brief.md)
- [Machine-readable completion record](../../.scratch/research/delegation-status.json)

The detached process was launched with `--model grok-4.7 --reasoning-effort high`. Its final event reports `stopReason: end_turn`, six turns, 42 tool calls, and usage under the backend name `grok-4.7-build`; the OS process exited 0. It ran from 21:43:42 to 21:48:55 UTC on 22 September 2026. No fallback model was requested. The report was read before this assessment was written.

The earlier Claude attempt exited without research; the user replaced that delegation with Grok. No pending Claude work is part of the final recommendation. No apps were installed, no source project was forked/imported, and no implementation decision has been recorded as accepted.
