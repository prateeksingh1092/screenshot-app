Grok 4.7 High produced this work.

Drag is a new exit through the shared finalization policy. `execute(.drag(revision, operation))` commits the rendered revision once and reports commit and delivery separately. The core interface is `DragCopyStaging`: `stage`, `promiseWriteReturned`, and `dragSessionEnded`. `DragHandoff.deliver` is the seam the recording stand-in implements. Only `.copy` proceeds; `.move` and `.delete` are rejected and do not touch History.

`DragStagingLifetime` writes that PNG under `staging/drag/`, which the launch sweep empties with the rest of `staging/`. The file is deleted only after both the promise write completion and the drag-session end, in either order. A failed promise write leaves the History row and image in place. The thumbnail starts an `NSFilePromiseProvider` whose dragging mask is `.copy` in both contexts, so a Trash drop cannot move or delete the History file.

New commit points: `dragStaged`, `dragPromiseWritten`. Tier 1 faults for both are in `DragHandoffTests`. Ticket 10's tier 2 harness must add a process-kill at each point, then rebuild, run recovery twice, and show the History image and row unchanged, `staging/drag` empty, and the second sweep identical. That includes a kill after only one of the two lifetime events.

`swift test --disable-sandbox --disable-keychain --disable-xctest --cache-path .build/cache --scratch-path .build --config-path .build/config --security-path .build/security`: **104 passed, 3 skipped**. Unsigned `xcodebuild -project Frisket.xcodeproj -scheme Frisket -configuration Development -destination 'platform=macOS,arch=x86_64' -derivedDataPath .build/DerivedData -clonedSourcePackagesDirPath .build/SourcePackages -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build` succeeded after `-resolvePackageDependencies` (GRDB 7.11.1).

**x86_64 macOS 26.7 (25G229); arm64 not executed.**

Prateek's manual check is `docs/manual-checks/12-drag-handoff.md`: drag the synthetic pattern into Finder and onto the Trash, verify the Finder PNG with `FrisketTestPattern --verify`, and confirm the History image remains. Stopped before review. Ticket status and checkboxes unchanged.

## Fix pass

Codex completed the ticket-12 fix brief on 2026-09-23, following implementation-workflow step 6 and the local TDD skill.

- **P1, session-end before destination:** accepted `.copy` sessions now wait for the promise destination. Cancelled or refused sessions without a promise still fail. The adapter holds the `NSFilePromiseProvider` until the write completion and session lifetime are finished.
- **P1, premature delivery:** separate started/handled flags prevent duplicate writes and session notifications during actor reentrancy. A write is handled only after the awaited filesystem write, its completion handler, and the lifetime event return. Delivery cannot report `.copied` while the write is pending or after that write fails.
- **P2, fault cleanup:** `dragPromiseWritten` runs before setting `writeReturned`, so an injected fault followed by session-end leaves staging for recovery.

TDD evidence: the extended core fault test first failed for both area and full-screen captures because session-end removed staging; it passes after the ordering fix. The delayed-destination regression first failed with `.failed` and no destination file. The suspended-write regression first exposed delivery before completion for both outcomes, including `.copied` when the write later failed. All now pass. Additional checks cover write-before-session completion and cancelled/move/delete session results. The focused run passed 10 tests across the two drag suites.

Full validation command, using Xcode and in-worktree caches:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
  swift test --disable-sandbox --disable-keychain --disable-xctest \
  --cache-path .build/cache --scratch-path .build \
  --config-path .build/config --security-path .build/security
```

Exit 0: Swift Testing reported **108 tests in 17 suites passed**, with three existing explicit skips (physical-footprint capture, recorded scroll sequences, and Vision alignment). Repository static checks and offline performance-tooling checks passed within that run.

The callback tests use the adapter's forwarded callback handlers and a controllable filesystem write boundary. Constructing a real file-promise provider in this sandbox raised `fileType 'public.png' is not a valid UTI`; the tests therefore avoid starting an AppKit drag. Finder/Trash and provider lifetime during a real drag remain manual checks; no app build or manual drag was rerun in this fix pass. No screen capture or clipboard operation was performed.

The duplicated Copy/Drag finalization heuristic remains open: it is a nonblocking extraction outside these correctness fixes. No broad review was relaunched. No git commands, ticket status edits, or checkbox edits were made.
