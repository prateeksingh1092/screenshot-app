Grok 4.7 High produced this work.

Drag is a new exit through the shared finalization policy. `execute(.drag(revision, operation))` commits the rendered revision once and reports commit and delivery separately. The core interface is `DragCopyStaging`: `stage`, `promiseWriteReturned`, and `dragSessionEnded`. `DragHandoff.deliver` is the seam the recording stand-in implements. Only `.copy` proceeds; `.move` and `.delete` are rejected and do not touch History.

`DragStagingLifetime` writes that PNG under `staging/drag/`, which the launch sweep empties with the rest of `staging/`. The file is deleted only after both the promise write completion and the drag-session end, in either order. A failed promise write leaves the History row and image in place. The thumbnail starts an `NSFilePromiseProvider` whose dragging mask is `.copy` in both contexts, so a Trash drop cannot move or delete the History file.

New commit points: `dragStaged`, `dragPromiseWritten`. Tier 1 faults for both are in `DragHandoffTests`. Ticket 10's tier 2 harness must add a process-kill at each point, then rebuild, run recovery twice, and show the History image and row unchanged, `staging/drag` empty, and the second sweep identical. That includes a kill after only one of the two lifetime events.

`swift test --disable-sandbox --disable-keychain --disable-xctest --cache-path .build/cache --scratch-path .build --config-path .build/config --security-path .build/security`: **104 passed, 3 skipped**. Unsigned `xcodebuild -project Frisket.xcodeproj -scheme Frisket -configuration Development -destination 'platform=macOS,arch=x86_64' -derivedDataPath .build/DerivedData -clonedSourcePackagesDirPath .build/SourcePackages -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build` succeeded after `-resolvePackageDependencies` (GRDB 7.11.1).

**x86_64 macOS 26.7 (25G229); arm64 not executed.**

Prateek's manual check is `docs/manual-checks/12-drag-handoff.md`: drag the synthetic pattern into Finder and onto the Trash, verify the Finder PNG with `FrisketTestPattern --verify`, and confirm the History image remains. Stopped before review. Ticket status and checkboxes unchanged.
