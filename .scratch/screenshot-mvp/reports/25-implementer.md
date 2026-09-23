Implemented ticket 25 with Grok 4.7 High. Stopped before review.

**Content model.** `OnboardingContent.current` is the only onboarding wording. It states the Screen Recording permission; History keeps finalized captures for 30 days or 1 GB, whichever limit is reached first (decision 5; decision 18 excludes exports from the 1 GB); Save keeps a permanent copy; and Frisket can remove captures only from itself, not from apps, devices, or backups it already delivered to. FileVault is recommended. `AboutContent` formats the bundle version, 0.1.0 (8), and the headings of bundled `THIRD-PARTY-NOTICES.md`. Decision 48 ported the stitcher, so About includes GRDB, the Matt Pocock skills, and the Snapzy stitcher. The brief's note that Snapzy was not ported does not match this tree.

**First launch.** `FirstLaunch` shows onboarding once. The flag is the bundle-scoped defaults key `hasCompletedOnboarding`, not a file under the History root. While a system alert is pending, the surface stays hidden. Continue closes onboarding, then hands off to ticket 23's recovery panel when permission is not granted. That panel still owns the explicit request and closes before the system alert. Later leaves the flag unset.

**Tests.** x86_64 macOS 26.7 (25G229); arm64 not executed.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift test --disable-sandbox --disable-keychain --disable-xctest --cache-path .build/cache --scratch-path .build --config-path .build/config --security-path .build/security
xcodebuild -project Frisket.xcodeproj -scheme Frisket -configuration Development -destination 'platform=macOS,arch=x86_64' -derivedDataPath .build/DerivedData -clonedSourcePackagesDirPath .build/SourcePackages -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build
```

Swift Testing: 101 passed, 3 existing opt-in tests skipped, 16 suites. Unsigned xcodebuild succeeded, and the notices file is in the app bundle.

**Prateek:** `docs/manual-checks/25-onboarding-and-about.md` covers first-launch copy, VoiceOver and keyboard, the permission handoff without covering the system alert, the once-only flag outside History, and About. Those checks were not run here.
