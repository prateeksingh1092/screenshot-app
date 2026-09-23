# Codex assessment of Cursor's Xcode necessity review

Status: independent response assessed; narrow compiler checks completed. No Xcode installed.

## Conclusion

**Full Xcode is not a universal prerequisite for a native macOS screenshot app.** The installed Command Line Tools compiled and linked a small Intel executable using AppKit, SwiftUI, ScreenCaptureKit and Vision, including a reference to the modern screenshot API. The executable ran successfully without taking a screenshot. My earlier categorical wording was too broad.

**Snapzy's existing source build and test workflow still depends on full Xcode.** The release checkout has an Xcode project rather than a root SwiftPM manifest, and depends on tooling absent from this installed CLT. Changing that is a build-system port, not simply choosing another editor.

This supports Cursor's central distinction. It does **not** prove a complete CLT-built screenshot app, successful screen-recording permission handling, working OCR, Swift Testing, signing persistence, or a passing Snapzy build.

## Independent evidence

Cursor ran through the user's existing Ultra account with requested model `claude-opus-5-5-high`; runtime identified `Claude Opus 5.5 300K High`. It completed with exit 0 at 2026-09-22 22:56:47 UTC. Its [original response](2026-09-22-cursor-xcode-necessity.md) is preserved separately. Cursor's web fetches were declined in that read-only session; its unvisited web references are not treated as fetched evidence.

Codex then verified:

| Check | Actual result |
|---|---|
| Installed compiler | Apple Swift 6.3.3; CLT SDK path `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`. |
| Positive framework probe | `swiftc` compile/link exit 0; x86_64 executable; run exit 0. Imports AppKit, SwiftUI, ScreenCaptureKit and Vision and type-checks a `SCScreenshotManager.captureImage` wrapper. Main only prints a success message. |
| SwiftUI preview probe | Type-check exit 1: `PreviewsMacros` plugin not found. |
| XCTest probe | Type-check exit 1: no such module `XCTest`. |
| Snapzy release source | Clean checkout at `837fc73d9b55dfde203e9d14aeb8c8fae4f0add7`; no root Package.swift; 64 source files contain `#Preview`; 156 test files import XCTest. |

Probe sources, negative compiler diagnostics, and positive run metadata are in `.scratch/evaluation/clt-probe/`. No capture, clipboard access, GUI launch, account change, certificate creation, or signing change occurred during these checks. Compiler cache and generated binary are ignored by Git; source and result records are retained.

Apple's official Command Line Tools documentation says `xcodebuild` and `xctrace` ship with Xcode rather than the CLT package. This agrees with the observed `xcodebuild` failure. [Apple: Installing the command-line tools](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools)

## Qualifications to Cursor's answer

- “CLT is enough for the MVP” is still a feasibility inference. Our positive probe proves framework compilation/linking and a no-capture executable, not the entire approved workflow.
- The missing Preview plugin and XCTest module are now observed failures, not guesses. Resource compilation, package embedding, permissions, and Swift Testing would still need targeted checks for any CLT-only foundation.
- Porting the source does not literally make evaluation impossible: it changes what is being evaluated and adds maintenance work. We should not discard the upstream tests merely to avoid an Xcode download.
- Cursor's proposed self-signed certificate/TCC strategy was not tested or adopted. No login-keychain changes are authorized by that report alone or required for the current compiler checks.
- We do not need a source build merely to inspect or manually evaluate the already-signed released Snapzy app. That can inform foundation selection while source-build tooling remains unresolved.

## Recommended next action

Continue evaluating the released Snapzy app and its adaptation surface without treating Xcode installation as a blanket blocker. If retaining Snapzy's existing build and tests is the chosen path, use an Intel-compatible full Xcode release. If the foundation choice shifts to a small fresh native app, evaluate a SwiftPM/CLT build and test setup instead. Do not silently turn this tooling question into approval of a new app architecture or a build-system rewrite.

The current App Store Xcode listing requires Apple M1 or later, so its latest release is not a suitable installation target for this Intel Mac. Xcode 26.6 appears in Apple's compatibility matrix for macOS Tahoe 26.x; its actual Intel installer must be confirmed before installation. [App Store requirements](https://apps.apple.com/us/app/xcode/id497799835?mt=12), [Apple compatibility matrix](https://developer.apple.com/xcode/system-requirements)

No final foundation decision or application implementation has been made. Resume from SESSION-CHECKPOINT.md and the approved product decisions, then continue the Pocock feasibility/specification process.
