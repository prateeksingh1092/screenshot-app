Implemented `dismiss`, `historyEntries()`, and lazy `HistoryStore` through the command layer/coordinator, with durable finalization, Copy retry consistency, and “Kept in History” feedback.

Commit points: `pngStaged`, `pngSynced`, `recordStaged`, `recordSynced`, `imageRenamed`, `recordRenamed`, `directorySynced`, `rowCommitted`, `thumbnailCached`.

Verification used `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and in-worktree caches:

- `sh scripts/test-core.sh`: **62 passed, 3 opt-in tests skipped**; includes 8 repository checks and 30 checker fixtures.
- `sh scripts/test-core.sh --filter HistoryCommandsTests`: **7 tests / 18 cases passed**, including all nine commit points.
- `swift build --disable-sandbox --disable-keychain --cache-path .build/cache --scratch-path .build --config-path .build/config --security-path .build/security`: passed.
- App-source `swiftc -typecheck`: passed. Unsigned `xcodebuild … CODE_SIGNING_ALLOWED=NO build`: attempted; package resolution blocked by Xcode’s manifest-cache write outside the sandbox. Xcode linking remains unverified.

**x86_64 macOS 26.7 (25G229); arm64 not executed.**

GRDB is statically linked, exactly **7.11.1**, revision `b83108d10f42680d78f23fe4d4d80fc88dab3212`, from `https://github.com/groue/GRDB.swift.git`. Both lockfiles contain only this approved pin; the linked licence notice is updated.

The coordinator’s exact resolution command and build/typecheck commands are in [app-build.md](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-09/docs/app-build.md). Outstanding journals return `recoveryRequired` without writes; recovery remains ticket 10.

Prateek’s manual items: synthetic Dismiss/Escape and Quit persistence, visual/VoiceOver feedback, Delete behavior, actual backup exclusion, and ticket 08’s permission/rebuild checks.

Stopped before review. Nothing staged or committed; ticket status and checkboxes unchanged.

## Coordinator evidence (2026-09-23 01:50–02:00, outside Codex's sandbox)

- The documented `xcodebuild -resolvePackageDependencies … -packageCachePath "$PWD/.build/cache" -onlyUsePackageVersionsFromResolvedFile` resolved **no packages**. It printed `resolved source packages:` with an empty list, and the build then failed with `Missing package product 'GRDB'`. The same happened after removing the stale `.build/SourcePackages` that the sandboxed attempt had left. `.build/cache` is also SwiftPM's cache path, so the two caches appear to collide.
- Without `-packageCachePath`, resolution works: `xcodebuild -resolvePackageDependencies -project Frisket.xcodeproj -scheme Frisket -derivedDataPath .build/DerivedData -clonedSourcePackagesDirPath .build/SourcePackages` resolved `GRDB @ 7.11.1`.
- The unsigned build then **succeeded**. It used `xcodebuild -project Frisket.xcodeproj -scheme Frisket -configuration Development -destination 'platform=macOS,arch=x86_64' -derivedDataPath .build/DerivedData -clonedSourcePackagesDirPath .build/SourcePackages -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build`.
- `docs/app-build.md` still documents the failing `-packageCachePath` form.
