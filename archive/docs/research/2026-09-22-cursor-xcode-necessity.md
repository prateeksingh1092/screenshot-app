# Cursor independent review: is full Xcode necessary?

Requested model: Claude Opus 5.5, high effort, through native Cursor.
Reported model: Claude Opus 5.5 300K High.
Status: completed independent response; [Codex assessment completed](2026-09-22-xcode-necessity-assessment.md).

The response below is preserved as returned. See the coordinating Codex assessment for verified claims, qualifications, and next steps.

---

I'll read the required rules and research skill first, then inspect Snapzy's build setup and the installed toolchain (read-only).Web fetches were declined, so I'm grounding the report in local primary sources instead: man pages, the SDK and PackageDescription interfaces, and SwiftPM's binaries.# Is full Xcode needed for screenshot-app?

*Produced by Claude Opus 5.5 at high effort in native Cursor. Read-only session: nothing was installed, built, or edited, and no tests were run. Web fetches were declined, so the Apple web documentation below comes from prior knowledge and is marked "not fetched"; Codex should verify it.*

## Observed toolchain

- `xcode-select -p` returns `/Library/Developer/CommandLineTools`. The Command Line Tools (CLT) package is version 26.6.0.0.1781586589.
- Swift is 6.3.3, targeting `x86_64-apple-macosx26.0`. The SDKs include `MacOSX26.5.sdk`, which `xcrun --show-sdk-version` reports as 26.5. The OS is macOS 26.7 (25G229) on x86_64.
- Present: `swift-build`, `swift-test`, `swift-run`, `ld`, `lipo`, `install_name_tool`, `/usr/bin/codesign`, `plutil`, `iconutil`, `sips`.
- The CLT also ships `SwiftBuild.framework` and `XCBuild.framework` under `usr/lib/swift/pm/`.
- `xcrun` cannot find `actool`, `ibtool`, `xcstringstool`, `xctest` or `momc`.
- The CLT test frameworks directory, `Library/Developer/Frameworks`, contains `Testing.framework` and `_Testing_AppKit.framework` but no `XCTest.framework`.
- The CLT macro plugins are `libObservationMacros`, `libSwiftMacros` and `testing/libTestingMacros`. There is **no `PreviewsMacros` plugin**.
- The SDK declares `#Preview` as `#externalMacro(module: "PreviewsMacros", type: "SwiftUIView")` (`MacOSX26.5.sdk/.../SwiftUI.swiftmodule/x86_64-apple-macos.swiftinterface:18521`).
- The SwiftPM manifest API offers `defaultIsolation(MainActor.self)`, `enableUpcomingFeature` and `unsafeFlags` (`usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule/x86_64-apple-macos.swiftinterface:63,88`).
- `man codesign` (line 553): a single `-` as the identity means ad-hoc signing, which "identifies exactly one instance of code."

## 1. Does a native macOS screenshot app need full Xcode?

**No, not inherently.** A `.app` is a directory: `Contents/MacOS/<binary>`, `Contents/Info.plist`, and optionally `Resources/` and `Frameworks/`. The CLT tools we observed can do every step:

- `swiftc` or SwiftPM compile AppKit, SwiftUI, ScreenCaptureKit and Vision against the 26.5 SDK.
- `plutil` writes `Info.plist`.
- `iconutil` makes the `.icns` icon.
- `codesign --sign - --options runtime --entitlements …` signs the bundle.

Screen Recording permission is granted per app by the privacy system (TCC), not by Xcode.

What you lose without Xcode is tooling, not capability:

- SwiftUI previews
- Asset catalog compilation (`actool`)
- String catalog compilation (`xcstringstool`)
- XCTest and UI tests
- Automatic signing and provisioning
- Instruments and the Xcode GUI debugger

**Inference with a caveat:** ad-hoc signatures change with every build. Snapzy's own docs say TCC then revokes permissions after each update (`Snapzy/docs/SELF_SIGNED_CERT.md:7`). For a personal build loop, a persistent self-signed certificate avoids repeated re-grants. That approach is shown in `scripts/create-signing-cert.sh` and needs no Apple account. Creating the certificate modifies the login keychain, so the user must approve that step.

## 2. Does Snapzy v1.32.3 unmodified need `xcodebuild` or full Xcode?

**Yes, as shipped.** Observed at commit `837fc73`:

- **No `Package.swift`.** The only build definition is `Snapzy.xcodeproj` (`objectVersion = 77`, `LastUpgradeCheck = 2620`, file-system-synchronized groups at `project.pbxproj:6,160,44-58`). Every script calls `xcodebuild`: `scripts/build_and_run.sh:196-278`, `scripts/run-tests.sh:151-172`, `scripts/launch.sh:117`, `scripts/test-tcc-local.sh:59`. My inference is that these project features need Xcode 16 or later, which makes the "Xcode 15.0+" note in `docs/BUILD.md:10` stale.
- **Resources that CLT can't compile:**
  - `Assets.xcassets` (AppIcon, AccentColor, MenubarIcon), with `ASSETCATALOG_*` settings at `project.pbxproj:392-394`.
  - 15 `.xcstrings` catalogs with `STRING_CATALOG_GENERATE_SYMBOLS = YES` (`:422`).
  - An Icon Composer `SnapzyIcon.icon`.
- **Macros:** 64 source files use `#Preview` without `#if` guards. Inference: under CLT `swiftc`, expanding `#Preview` should fail because the `PreviewsMacros` plugin is missing.
- **Tests:** 156 test files `import XCTest`, which is absent from CLT. The test plan is `Snapzy.xctestplan`, so `swift test` cannot run the existing suite.
- **Signing:** the project uses Automatic signing with `DEVELOPMENT_TEAM = XMHV5GH2Z7` (the upstream author's team), hardened runtime on and sandbox off (`:395-401`). The entitlements use `$(PRODUCT_BUNDLE_IDENTIFIER)` (`Snapzy.entitlements:21-22`), which plain `codesign` doesn't expand (`scripts/test-tcc-local.sh:96`).
- **Packages** (`project.pbxproj:555-580`, `Package.resolved`): Sparkle 2.8.1, Swift-WebP 0.6.1 (with libwebp-Xcode 1.5.0) and GRDB 7.10.0. These are ordinary SwiftPM packages. Inference: Sparkle is a binary XCFramework whose XPC services would need manual embedding and re-signing, as `test-tcc-local.sh:34-42` shows.

**A SwiftPM or manual port is feasible but invasive** (inference). You would need to:

- Write a `Package.swift` with `defaultIsolation(MainActor.self)` plus upcoming-feature flags to match `SWIFT_APPROACHABLE_CONCURRENCY` and `SWIFT_DEFAULT_ACTOR_ISOLATION`.
- Remove or guard all 64 `#Preview` blocks.
- Replace the asset catalog with loose PNG files and an `iconutil` `.icns`.
- Accept English-only UI or hand-convert the catalogs. `L10n.string` passes `defaultValue` (`Snapzy/Shared/Localization/L10n.swift:94-101`), so English likely still renders.
- Embed and re-sign Sparkle, or remove its 8 imports.
- Pre-process the entitlements.
- Give up the XCTest suite.

At that point you'd be evaluating a fork, not Snapzy.

## 3. Evidence we can get with the installed CLT

This is a proposed proof for the parent to run afterward inside the workspace, for example in `.scratch/probe/`.

**Positive probe:** a single-file app that captures the screen and runs OCR on it.

```swift
import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision

@main @MainActor
final class Probe: NSObject, NSApplicationDelegate {
  static func main() {
    let app = NSApplication.shared
    let delegate = Probe()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let panel = NSPanel(contentRect: NSRect(x: 40, y: 40, width: 220, height: 60),
                        styleMask: [.nonactivatingPanel, .titled], backing: .buffered, defer: false)
    panel.level = .floating
    panel.contentView = NSHostingView(rootView: Text("probe").padding())
    panel.orderFrontRegardless()
    Task {
      do {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else { print("no display"); NSApp.terminate(nil); return }
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        let image = try await SCScreenshotManager.captureImage(
          contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)
        let request = VNRecognizeTextRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        print("captured \(image.width)x\(image.height); text regions \(request.results?.count ?? 0)")
      } catch { print("error: \(error)") }
      NSApp.terminate(nil)
    }
  }
}
```

```bash
swiftc -parse-as-library -target x86_64-apple-macos14.0 main.swift -o Probe
mkdir -p Probe.app/Contents/MacOS && mv Probe Probe.app/Contents/MacOS/
plutil -create xml1 Probe.app/Contents/Info.plist
plutil -insert CFBundleIdentifier -string dev.prateek.probe Probe.app/Contents/Info.plist
plutil -insert CFBundleExecutable -string Probe Probe.app/Contents/Info.plist
plutil -insert CFBundlePackageType -string APPL Probe.app/Contents/Info.plist
codesign --force --sign - --options runtime Probe.app && codesign -dv Probe.app
open -W --stdout "$PWD/out.txt" --stderr "$PWD/err.txt" Probe.app; cat out.txt err.txt
```

Launch it with `open`, not by running the binary directly: running from a terminal makes TCC treat Cursor or Terminal as the responsible app. Grant permission in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch. Next, rebuild, re-sign and relaunch to see whether the ad-hoc grant survives. The expected result, per Snapzy's docs, is that it doesn't.

**Negative probes**, which confirm the Snapzy blockers:

- `printf 'import SwiftUI\n#Preview { Text("x") }\n' > p.swift && swiftc -typecheck p.swift` should fail because `PreviewsMacros` isn't found.
- `printf 'import XCTest\n' > t.swift && swiftc -typecheck t.swift` should fail with "no such module".

**Optional:** a SwiftPM package with `defaultIsolation(MainActor.self)` and one `import Testing` test, run via `swift test`, to check that Swift Testing works under CLT alone.

## 4. Is paid Apple Developer membership needed?

**Not for personal or local builds.**

- Ad-hoc signing (`codesign -s -`) and a self-signed certificate need no account (`man codesign:553`; `Snapzy/docs/SELF_SIGNED_CERT.md:64-66`).
- Xcode itself is free, and a free Apple ID gives a "Personal Team" for local signing (not fetched).
- Paid membership is only needed for **Developer ID** signing and **notarization**, which let other people's Macs pass Gatekeeper without warnings (`SELF_SIGNED_CERT.md:64`; Apple's "Notarizing macOS software before distribution", not fetched).
- On Intel, the macOS 11 rule that native code must be signed applies only to arm64 (Apple's macOS 11 release notes, not fetched). The signing concern here is keeping TCC permissions stable, not whether the app launches.

## 5. Least-friction path now

1. **Run the CLT proof first.** It's cheap and settles questions 1 and 3 with evidence.
2. **To evaluate Snapzy itself as-is:** install the free full Xcode. Porting its build plumbing to CLT costs more than the download and turns the evaluation into a fork. Condition to check: the current Xcode 26.x must support Intel on macOS 26.7 (unverified).
3. **For a fresh native foundation:** CLT is enough for the MVP. Use a SwiftPM executable, a small bundling and signing script, Swift Testing, loose resources, and no `#Preview`. Add Xcode later only for previews, Instruments, asset or string catalogs, or UI tests.

**Uncertainties:**

- Whether SwiftPM on CLT compiles `.xcstrings`. The `XCStrings.xcspec` file is present but the `xcstringstool` binary is not.
- Whether `swift test` with Swift Testing works end to end under CLT.
- Whether a self-signed identity keeps TCC grants across rebuilds on macOS 26.7.

## Did Codex overstate the need for Xcode?

**Partly.** "Full Xcode is needed" is **true for building and testing Snapzy unmodified**, because of the `xcodeproj`, the 64 `#Preview` files, the asset and string catalogs, and the XCTest suite. It is **overstated as a general requirement for a native macOS screenshot app**: the installed CLT should be able to compile, bundle, ad-hoc or self-sign, and run an AppKit/SwiftUI/ScreenCaptureKit/Vision `.app`. The proof in section 3 is the experiment that confirms this.
