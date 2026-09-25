# Snapzy v1.32.3 network and local-only surface

Date: 2026-09-22. Status: source-only research for stack assessment evidence item 6 ("verify local-only behavior"). No build, launch, capture, or network trace was performed. This is not a foundation selection.

Provenance: Cursor native Claude Opus 5.5 High, complementary to Codex (GPT-6 Astra, high) as lead, which is concurrently covering the history/redaction lifecycle in [the adaptation report](2026-09-22-snapzy-history-adaptation.md). Prateek directed that a Codex review of this report is not required.

Scope: release checkout `.scratch/evaluation/Snapzy/` at tag v1.32.3, commit `837fc73d9b55dfde203e9d14aeb8c8fae4f0add7`. Paths below are relative to that checkout. Findings about master `9f48e030` in the earlier stack report are not re-asserted here.

## Conclusion

**Out of the box, v1.32.3 makes no network request that carries capture content.** Default OCR is on-device Vision, cloud upload requires explicit configuration and a user action, and there is no telemetry SDK. The only default-reachable outbound traffic is Sparkle's update check, and it requires the user to consent on the second launch.

The approved "local storage first, no recurring service" direction is therefore satisfiable by **removing or disabling code, not rewriting it**. Two findings matter more for adaptation than for privacy. First, the upstream update feed would offer upstream builds to an adapted fork. Second, the `snapzy://` URL scheme lets other apps trigger captures that, by default, are saved and copied without further interaction.

## Observed egress points

| Surface | Trigger and default | Carries capture bytes? | Evidence |
|---|---|---|---|
| Sparkle updates | Updater starts at launch. `SUEnableAutomaticChecks` is unset, so checks start disabled and Sparkle asks the user on the second launch. Feed is `raw.githubusercontent.com/.../master/appcast.xml`, verified with an EdDSA key. | No | `Snapzy/Services/Updates/UpdaterManager.swift:32-36`; `Snapzy/Resources/Info.plist:50-55`; toggles at `Snapzy/Features/Preferences/Components/PreferencesGeneralSettingsView.swift:71-84`; [Sparkle customization docs](https://sparkle-project.org/documentation/customization/) |
| Remote OCR | Only when the user adds a custom model and selects it; missing, corrupt, or unknown selections fall back to built-in Vision. | **Yes** (image sent to the user-defined OpenAI-compatible endpoint) | `Snapzy/Services/Media/OCR/OCRModelResolver.swift:64-76, 111-122`; request at `RemoteOCRService.swift:117` |
| Cloud upload (S3, R2, Google Drive) | Only from UI actions: Quick Access card, Annotate, History, Video Editor. `upload` throws `notConfigured` without a provider. | **Yes**, to the user's own storage | `Snapzy/Services/Cloud/CloudManager.swift:594-605`; callers `Features/QuickAccess/Components/QuickAccessCardView.swift:709`, `Features/Annotate/Managers/AnnotateWindowController.swift:1272, 1366`, `Features/History/Managers/HistoryFloatingManager.swift:355` |
| Cloud usage queries | From the Cloud settings pane; needs a stored configuration. | No (bucket metadata) | `Features/Preferences/Components/PreferencesCloudSettingsView.swift:506, 1344`; `Services/Cloud/CloudUsageService.swift:278-280` |
| Google OAuth loopback | `NWListener` bound to 127.0.0.1 only during Drive sign-in; browser opened for consent. | No | `Services/Cloud/GoogleDriveOAuthService.swift:74, 102, 190-194` |
| Outbound links | User clicks: bug-report page, sponsor/about links, links detected in OCR text (floating prompt, auto-dismisses after 10 s). | No automatic payload; the diagnostic zip is attached manually | `Features/CrashReport/CrashReportService.swift:13, 33-37`; `Features/Capture/OCRLinkPromptManager.swift:17, 42-50` |

Dependencies pinned in `Snapzy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`: GRDB 7.10.0, Sparkle 2.8.1, Swift-WebP 0.6.1, libwebp-Xcode 1.5.0. None is an analytics or crash-upload SDK. A search of the app sources for `URLSession`, `NWConnection`, `NWListener`, and upload APIs found no other network call sites.

## Process boundaries

- **Not sandboxed.** `ENABLE_APP_SANDBOX = NO` with hardened runtime on, in both configurations (`Snapzy.xcodeproj/project.pbxproj:400-401, 442-443`). The `network.client`/`network.server` keys in `Snapzy/Snapzy.entitlements:5-8` therefore do not constrain anything. The README states this openly (`README.md:262`).
- `SUEnableInstallerLauncherService = YES` (`Info.plist:54-55`). Sparkle's documentation says not to enable this service for apps that aren't sandboxed. Inference: harmless to privacy, but a configuration to correct in any fork.

## Upstream documentation versus code

`README.md:262` lists "optional user-initiated OCR model downloads from HTTPS/Hugging Face sources" as a network path. No Hugging Face or model-download code remains in the release app sources. `OCRModelResolver.swift:70-72` says the downloadable provider was removed and migrates old `dl:` selections to built-in. The claim is stale in the safe direction. The rest of the README's network statement (Sparkle, loopback OAuth, user-initiated uploads, custom OCR endpoints, no telemetry) matches the code paths observed above. Do not rely on upstream prose as proof for later releases; recheck the code.

## Local, non-network surface relevant to "narrow feature surface"

- **URL scheme enabled by default.** `SnapzyDeepLinkHandler.swift:20` treats a missing preference as enabled. Routes include full-screen capture, window capture, OCR, screen recording, and opening history (`:51-99`, route table `:124-179`). None of them uploads.
- **Default after-capture actions** are Quick Access, save, and copy to clipboard all on; opening Annotate is off (`Features/Preferences/PreferencesManager.swift:173-180`).
- Inference: any local process, or a web page after the browser's external-app prompt is accepted, can produce a full-screen capture that lands on disk and the pasteboard. For a personal-first app this is a local privacy exposure, not network exfiltration. Separately, the default save-and-copy behavior needs reconciling with accepted decision 5; Codex's adaptation report owns that lifecycle question.
- Diagnostic logs are local files under the app's `Logs` directory with a configurable retention (`Services/Diagnostics/DiagnosticLogger.swift:102-111`; `PreferencesKeys.swift:160`). They record hosts, file names, and deep-link URLs, not image bytes or OCR text in the paths inspected. Not exhaustively audited.

## Required adaptation changes (proposed, not accepted)

1. **Update channel.** Replace `SUFeedURL` and `SUPublicEDKey` with the fork's own, or remove Sparkle for personal builds. Keeping upstream values means Sparkle would offer and validate upstream releases over the adapted app. Inference from Sparkle's EdDSA model; not tested.
2. **Out-of-scope network features.** Recording, cloud, and hosted sharing are deferred. Exclude the `Services/Cloud/` providers, their UI entry points, and the Google OAuth listener at compile time, not only by hiding menu items. Custom OCR endpoints should be removed or gated behind an explicit decision, because they send captured images off-device.
3. **URL scheme.** Default it off, or restrict it to non-capturing routes, pending a product decision. Record this as an open question, not a requirement.
4. **Configuration import.** `Services/Configuration/SnapzyConfigurationImporter.swift:133-136` can enable automatic update checks and downloads from an imported TOML file. If import is kept, apply the same policy to it.

## Proposed verification cases for a later evaluation ticket

1. Fresh profile, first and second launch, offline and online. Record every outbound connection, for example with the macOS network privacy report or a local proxy. Expect none except the second-launch Sparkle consent prompt, and nothing after declining.
2. Capture area, window, and full screen; run OCR, annotate, copy, save, and drag. Expect zero outbound connections throughout.
3. With the scheme enabled, run `open snapzy://capture/fullscreen` from Terminal and record what is written to disk and the pasteboard. Repeat after the adaptation default changes.
4. After removing the cloud and remote-OCR code, check with `nm`/`strings` that the built binary no longer contains the S3, Drive, or OCR endpoint client paths.
5. Import a TOML with `check_automatically = true` and confirm that the adapted policy wins.

## Remaining uncertainty

- Source analysis only. The signed release DMG's embedded `Info.plist` and entitlements were not re-inspected for this report. Runtime traffic is inferred from code paths, not measured.
- Behavior of Sparkle 2.8.1 when an update's EdDSA signature is valid but its Developer ID team differs from the running fork's was not verified.
- Searches were keyword-based over `Snapzy/`. A dynamically constructed network call outside the searched APIs would be missed. The runtime trace in case 1 closes that gap.
