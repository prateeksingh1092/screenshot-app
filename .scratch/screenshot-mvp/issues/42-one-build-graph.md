# 42: One build graph for the app and the package

**What to build:** The app and the package tests compile the core from one build graph, so what the tests verify is what ships. The app links the package's `FrisketCore` product instead of compiling its own copy. GRDB is pinned once. The SDK follows the installed Xcode. The signing identity comes from an untracked local file, so a beta tester can build without editing the project.

**Blocked by:** None — can start immediately

**Phase:** 0 (O13 step 1)

**Status:** ready-for-agent

- [ ] The Xcode project has no `FrisketCore` static-library target; the app depends on the package's `FrisketCore` product through a local package reference.
- [ ] GRDB is pinned only in the package manifest, and the project reads the root `Package.resolved` (one file, not two copies).
- [ ] `SDKROOT` is `macosx`, with no hard-coded SDK version.
- [ ] Development team, signing style and identity come from an untracked `Signing.xcconfig`, with a tracked example beside it. Without it the build signs ad hoc, and the build doc warns that an ad-hoc build loses the Screen Recording grant on every rebuild (decision 49).
- [ ] The project carries no zlib or libcompression linker flags of its own; the package supplies them until ticket 67 deletes them.
- [ ] The unsigned Development build and the package suite pass. The built app keeps its bundle identifier, entitlements, hardened runtime and Info.plist keys.
- [ ] The app still compiles `Frisket/Adapters` itself (step 2 is ticket 77).

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
