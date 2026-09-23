Added `captureFullScreen` and **Capture Full Screen**, a menu-only action capturing the pointer’s display at native scale through ScreenCaptureKit’s own-app exclusion filter, into a Pending capture and thumbnail. No second Carbon hot key; shortcuts/remapping remain ticket 24.

Verification: **x86_64 macOS 26.7 (25G229); arm64 not executed**.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift test --disable-sandbox --disable-keychain --disable-xctest \
  --cache-path .build/cache --scratch-path .build \
  --config-path .build/config --security-path .build/security
xcodebuild -project Frisket.xcodeproj -scheme Frisket \
  -configuration Development -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath "$PWD/.build/DerivedData" CODE_SIGNING_ALLOWED=NO build
```

- Targeted test: same Swift command plus `--filter FullScreenCaptureCommandsTests`; red compilation failure before implementation, then green: 1 test with 3 display cases.
- Full suite: 59 tests reported across 9 suites—56 passed, 3 existing opt-in skips; zero failures. Includes 8 repository checks and 28 checker fixtures.
- Unsigned app build passed. Synthetic helper compiled; five verifier checks passed, including rejection of incorrect dimensions and marker pixels.
- `git diff --check` passed.

Prateek: run [the manual checklist](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-20/docs/manual-checks/20-full-screen-capture.md) on Retina 2×, external 1×, and negative-coordinate displays. Verify native pixels, thumbnail placement, own-app exclusion, Copy/Delete, and permission failures. Full-screen capture requires explicit approval under decision 50, even with synthetic coverage.

Stopped before review, staging, or commit; ticket status/checkboxes unchanged. Report saved as `.scratch/screenshot-mvp/reports/20-implementer.md`.
