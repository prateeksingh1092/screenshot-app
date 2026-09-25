# 42: One build graph for the app and the package

**What to build:** The app and the package tests compile the core from one build graph, so what the tests verify is what ships. The app links the package's `FrisketCore` product instead of compiling its own copy. GRDB is pinned once. The SDK follows the installed Xcode. The signing identity comes from an untracked local file, so a beta tester can build without editing the project.

**Blocked by:** None — can start immediately

**Phase:** 0 (O13 step 1)

**Status:** resolved (tested on `main` at `51a6277`)

- [x] The Xcode project has no `FrisketCore` static-library target; the app depends on the package's `FrisketCore` product through a local package reference.
- [x] GRDB is pinned only in the package manifest, and the project reads the root `Package.resolved` (one file, not two copies).
- [x] `SDKROOT` is `macosx`, with no hard-coded SDK version.
- [x] Development team, signing style and identity come from an untracked `Signing.xcconfig`, with a tracked example beside it. Without it the build signs ad hoc, and the build doc warns that an ad-hoc build loses the Screen Recording grant on every rebuild (decision 49).
- [x] The project carries no zlib or libcompression linker flags of its own; the package supplies them until ticket 67 deletes them.
- [x] The unsigned Development build and the package suite pass. The built app keeps its bundle identifier, entitlements, hardened runtime and Info.plist keys.
- [x] The app still compiles `Frisket/Adapters` itself (step 2 is ticket 77).

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: coordinator, resolved

- **Implementer:** the coordinator (Claude Opus 5.5, Claude Code, medium effort), on branch `ticket/42-one-build-graph`.
- **Change:** the project replaces the `FrisketCore` static-library target and its GRDB pin with `XCLocalSwiftPackageReference(relativePath: ".")` and a `FrisketCore` product dependency. The workspace `Package.resolved` is a symlink to the root one. `SDKROOT = macosx`. Signing moved to `Config/Frisket.xcconfig`, which is ad hoc by default and `#include?`s the untracked `Config/Signing.xcconfig`, documented by `Signing.example.xcconfig`. `OTHER_LDFLAGS` is gone because the package supplies `-lz -lcompression`.
- **Evidence (x86_64 only; arm64 compiled, never executed):**
  - A clean unsigned Development build into fresh derived data succeeded. Core and GRDB were compiled from the package.
  - The universal unsigned Release build succeeded (`lipo`: x86_64 arm64).
  - Info.plist has the same 23 keys and values as before. `showBuildSettings` for Development and Release differ only by the removed `OTHER_LDFLAGS`. The binary still links `libz` and `libcompression`.
  - Without `Signing.xcconfig`, the build resolves to `CODE_SIGN_IDENTITY = -`.
  - `swift test`: 286 tests in 44 suites passed.
  - New offline `BuildGraphTests` in `Tools/Release/test_project.py` fail on the old project and pass on the new one.
- **Not done here:** the "Reject Event Taps and Global Monitors" build phase stays until ticket 43 moves it into `ci.sh`.
