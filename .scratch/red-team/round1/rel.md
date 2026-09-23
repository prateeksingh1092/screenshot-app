<!-- Provenance: Cursor Claude Opus 5.5 High subagent b0a2d7aa-d91a-4906-97a3-fb51923a932c, round 1, 2026-09-22. Final response saved by the facilitator. -->

## Release, licensing, and distribution engineer (REL): round 1

### Findings

**REL-1: Ported code keeps Snapzy's identity: shared data with installed Snapzy, Snapzy name on output**
- Target: decisions 13, 22
- Attack: Code slated for porting hard-codes Snapzy names and paths: database at `Application Support/Snapzy/snapzy.db`; thumbnails and sessions under `Snapzy` directories; keychain service `com.trongduong.snapzy.ocr`; default watermark text `"Snapzy"`. Decision 22 runs the signed Snapzy release on this same Mac, so the new app could open Snapzy's database and decision 18's eviction could delete Snapzy's files. A default "Snapzy" watermark risks the license's no-endorsement clause 3.
- Severity: blocker
- Evidence: `Snapzy/Services/Cloud/DatabaseManager.swift:43,166`; `Services/History/HistoryThumbnailGenerator.swift:59`; `Features/Annotate/Services/AnnotationSessionStore.swift:234`; `Services/Security/OCRKeychainStore.swift:40`; `Features/Annotate/Services/AnnotateAnnotationRenderer.swift:142`; `AnnotateState.swift:249`; `LICENSE:15-17`.
- Amendment: Identity-scrub gate: `rg -i 'snapzy|trongduong'` over app sources matches only license headers and the notices file. Fixture test: every app-owned path derives from the new bundle identifier.
- Changes an accepted product decision (1-12): no

**REL-2: BSD-3 obligations lack a mechanism; upstream files have no headers to retain**
- Target: decision 13
- Attack: No Snapzy source file carries a copyright line (headers name only the file, e.g. `AppCoordinator.swift:1-6`). Clause 1 still requires redistributed source to retain the notice; clause 2 requires it in binary documentation. No plan item covers either.
- Severity: major
- Evidence: `LICENSE:7-13`; a search of 475 Swift files found no copyright or license header.
- Amendment: Every ported file starts with `SPDX-License-Identifier: BSD-3-Clause`, `Copyright (c) 2026, Trong Duong Duc`, and "Derived from Snapzy v1.32.3 (837fc73d) `<upstream path>`". Add `provenance/snapzy.json` mapping each ported file to its upstream path and blob SHA (`git rev-parse 837fc73d:<path>`), like `.cursor/skills/matt-pocock/provenance.json`. A check script fails on header/manifest mismatch either way. Copy `THIRD_PARTY_NOTICES` into `Contents/Resources` and show it from About/Acknowledgements; test that it exists in the built bundle.
- Changes an accepted product decision (1-12): no

**REL-3: Porting can drag in Sparkle and WebP**
- Target: decisions 13, 20, 21
- Attack: Fourteen Snapzy files import GRDB, Sparkle or WebP. The database manager lives under `Services/Cloud/`. `AnnotateExporter.swift:218-220` calls `WebPEncoderService`. Decisions 20 (PNG only) and 21 (no updater) mean Sparkle and WebP should never enter, but nothing enforces it.
- Severity: major
- Evidence: `Package.resolved:3-39`. GRDB 7.10.0 is MIT ([LICENSE](https://raw.githubusercontent.com/groue/GRDB.swift/v7.10.0/LICENSE)); Swift-WebP is MIT ([LICENSE](https://raw.githubusercontent.com/ainame/Swift-WebP/0.6.1/LICENSE)). Sparkle and libwebp licenses not fetched.
- Amendment: Dependency allowlist `{GRDB}`. A check fails if `Package.resolved` has any other pin or `rg 'import (Sparkle|WebP)'` matches. GRDB's MIT notice in `THIRD_PARTY_NOTICES`. Link GRDB statically (inferred SwiftPM default) so library validation can't block loading; verify with `otool -L` (no GRDB dylib).
- Changes an accepted product decision (1-12): no

**REL-4: "Locally signed" is undefined; ad-hoc signing loses Screen Recording every build**
- Target: decision 21
- Attack: Apple: an ad-hoc signature's designated requirement "is tied to that specific version of the code", so macOS "can't reliably track the identity"; the TCC grant disappears per rebuild. Apple Development pins the leaf certificate's common name; Developer ID produces a different requirement, so identity migration always costs one re-grant.
- Severity: major
- Evidence: [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements); `docs/SELF_SIGNED_CERT.md:7,60-74`.
- Amendment: "Locally signed" = an Apple Development identity from a free Xcode Personal Team, or a persistent self-signed certificate; never ad-hoc for the installed copy. Hardened runtime on; no `get-task-allow` on the installed build; fixed install path. Acceptance: grant, rebuild and re-sign, relaunch with `open`, grant survives; record `codesign -d -r-`. Creating either identity changes Prateek's Xcode account or keychain, so he must approve.
- Changes an accepted product decision (1-12): no

**REL-5: Bundle identifier is unchosen but effectively permanent**
- Target: decision 21 (gap)
- Attack: The bundle ID keys TCC grants, UserDefaults, Application Support, keychain items and a future Developer ID App ID. Changing it later strands history and permissions. It must not be under `com.trongduong.*`. Personal Team App IDs "expire after 7 days" ([Apple](https://developer.apple.com/support/compare-memberships/)), so registering one does not reserve the name (inference).
- Severity: major
- Evidence: `project.pbxproj:417,458`; Apple page above.
- Amendment: Add a decision fixing the bundle ID as a reverse-DNS name Prateek controls, or `io.github.<handle>.<app>`. Development builds use a `.debug` suffix so they don't touch the installed copy's permissions or history.
- Changes an accepted product decision (1-12): no

**REL-6: Universal binary requires Xcode; arm64 can't run here**
- Target: decisions 14, 15
- Attack: Apple: "Xcode 12.2 and later is a requirement for building universal binaries"; "you cannot debug the arm64 slice … on an Intel-based Mac". Inference: the CLT-only package build is x86_64 only, and arm64 never runs anywhere in v1.
- Severity: major
- Evidence: [Building a universal macOS binary](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary).
- Amendment: "Universal" gates only the Xcode release build: `lipo -archs` shows both; `codesign --verify --strict --deep --verbose=2` and `codesign -dv --arch arm64` pass. Label arm64 "built and signed, never executed" until an Apple silicon test exists.
- Changes an accepted product decision (1-12): no

**REL-7: What distribution prep costs nothing now**
- Target: decisions 9, 21
- Attack: Only Developer ID-signed software can be notarized, and only a paid Apple Developer Program Account Holder can create that certificate. Without a firm rule, self-signed builds may later be handed out with "right-click, Open" instructions.
- Severity: minor
- Evidence: [notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues); [Developer ID](https://developer.apple.com/developer-id/).
- Amendment: Record that distribution beyond this Mac needs a separate paid decision. Free now: hardened runtime; a minimal entitlements file (do not copy `Snapzy.entitlements` with camera, audio, network and temporary-exception keys); signing identity as one build variable; a packaging script that exists but has not been run. Never port `SUFeedURL`/`SUPublicEDKey` (`Resources/Info.plist:50-52`).
- Changes an accepted product decision (1-12): no

**REL-8: The first commit would pick up third-party and license-quarantined material**
- Target: gap
- Attack: No commits yet; everything untracked. `.scratch/research/github/` holds copied third-party files, including Capso's Business Source License 1.1 and Cap's mixed-license text, which a porting agent could mistake for permitted sources. `SESSION-CHECKPOINT.md`, `AGENTS.md`, `docs/agents/cursor-workflow.md` contain `/Users/16intelmac` paths. No project `LICENSE`. `.gitignore` covers only evaluation paths. Keyword search found only prose mentions of secrets; no dedicated scanner run.
- Severity: major
- Evidence: `git status`; `.gitignore:1-4`; `lzhgus--Capso--LICENSE:1`.
- Amendment: Before the first commit: project `LICENSE`; `THIRD_PARTY_NOTICES` (Snapzy BSD-3, GRDB MIT, copied skills MIT); extend `.gitignore` (`.build/`, `DerivedData/`, `xcuserdata/`, `.DS_Store`, `*.p12`, `*.cer`, `*.mobileprovision`, `*.app`, `*.dmg`, `.env`); ignore `.scratch/research/github/` or add a rule that only Snapzy may be ported; review the staged diff for secrets; keep the repo private until Prateek decides otherwise.
- Changes an accepted product decision (1-12): no

### Keep
- Decision 13: porting under a permissive license instead of forking avoids inheriting the upstream signing team and appcast.
- Decision 19: no URL scheme or App Intents in v1 keeps entitlements and attack surface minimal.
- Decision 21: any update feed belongs to this project, never upstream.

### Questions only Prateek can answer
1. Product name and domain or GitHub handle for the bundle identifier?
2. License for the project's own code; will the repo ever be public?
3. May a signing identity be created (Xcode Personal Team sign-in, or a self-signed certificate in the login keychain)?
