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
