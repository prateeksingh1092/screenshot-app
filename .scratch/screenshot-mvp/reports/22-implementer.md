# Ticket 22 implementer report

Model: Codex GPT-6 Astra, medium. Stopped before review; ticket status and checkboxes unchanged.

Implemented an empty-default, bundle-scoped persisted Capture exclusion list with Settings Add App/Remove controls. Application identities stay out of diagnostics. Area and full-screen requests include current exclusions plus Frisket; the shared ScreenCaptureKit filter and frozen magnifier previews exclude matching applications while retaining fail-closed self-exclusion.

Window and scrolling capture commands are absent from this base. Their integration must use the shared policy; their runtime coverage remains pending.

Validation on x86_64, macOS 26.7 (25G229), Xcode toolchain:
- Seam 1 red→green: area list edits/default/self-exclusion; full-screen edits and exact closed diagnostic events. Both passed.
- Full Swift Testing run: 118 tests reported: 115 passed, three opt-in tests skipped, including repository checks.
- All app sources: Swift 6 typecheck passed.
- Fixed eight pre-existing Save test constructors missing the required granted-permission fixture, which otherwise blocked compilation.

Build seed had relocated caches and no GRDB checkout. Initial SwiftPM attempts invoked dependency fetching despite skip/resolution flags; one failed and the other was interrupted. Subsequent builds used the locally cached pinned checkout through a temporary local-path manifest. Original manifest and lockfile restored. Full suite ran through Xcode's SwiftPM testing helper without resolution. Logs: `.build/ticket22-*.log`.

No app launch, capture, clipboard, signing, or review performed. Arm64 not executed. Synthetic-only operator checklist, not run: `docs/manual-checks/22-capture-exclusion-list.md`. UI behavior and preference persistence await that checklist.

## Fix pass

Model: Codex GPT-6 Astra, high. Addressed the justified P1 in `22-code-review-codex.md`; no broad review relaunched.

Final area/full-screen capture now fetches current ScreenCaptureKit shareable content after selection, immediately before constructing its application filter. A refresh failure fails closed without falling back to prefetched identities. Each frozen magnifier preview also refreshes its content. The original permission-before-selection prefetch remains intact.

Application launch/termination notifications are observed from prefetch through completion. Changes during snapshot refresh or screenshot delivery invalidate the result; previews are discarded and observers removed at completion. This conservatively invalidates on any application's launch/termination. The screenshot API has no in-flight filter-update operation, so affected images are rejected rather than delivered. SDK evidence: `SCShareableContent.h`, `SCStream.h`, and `SCScreenshotManager.h` in Xcode's macOS SDK. Real OS notification timing and pixel exclusion remain manual verification items.

Added an injectable ScreenCaptureKit snapshot/screenshot boundary. Regression tests exercise the real `ScreenCapturePlatform.capture` path with synthetic process identities and PNG pixels, without obtaining screen pixels or opening selection UI:
- Launch during selection: observed red canary leakage before the fix, then verified its absence after refreshing identities; also covers relaunch with a different PID.
- Launch/termination during asynchronous screenshot delivery: observed incorrect success before the guard, then verified rejection.
- Snapshot refresh failure: verifies unavailable rather than stale-content fallback.

Validation used Xcode and in-worktree caches on x86_64:
- Focused red/green logs: `.build/ticket22-fix-{red-local,green-launch,red-changes,green-changes}.log`.
- Full `swift test` was attempted. Original-manifest dependency resolution failed against the missing GRDB repository cache. Using the existing GRDB checkout through a temporary local-path manifest built and ran all tests; only the repository dependency-source check rejected that temporary manifest, as expected. Manifest and lockfile were restored afterward.
- Reran the entire built suite with the original manifest/lockfile through Xcode's `swiftpm-testing-helper`, passing the test bundle's executable path, `--testing-library swift-testing`, and Xcode's Testing framework search path. **121 tests reported, 118 passed and three opt-in tests skipped; all eight repository checks passed.** Log: `.build/ticket22-fix-full-suite-restored.log`.
- All app sources passed Swift 6 typechecking. Log: `.build/ticket22-fix-typecheck.log`.

No remaining code finding from this review. Window/scrolling exclusions remain the explicit integration follow-up after tickets 21/35 merge; those commands were not fabricated. No git commands, ticket Status/checkbox changes, app launch, real capture, clipboard use, or signing performed. Arm64 and manual capture/UI checks remain unexecuted.
