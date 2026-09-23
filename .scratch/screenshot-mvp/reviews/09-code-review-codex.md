# Ticket 09 — fresh Codex review (GPT-6 Astra, high), 2026-09-23

Fixed point `11aeb4b`.

## Standards

- **Should-fix — `docs/app-build.md:148`:** the resolver command still has the known-broken `-packageCachePath "$PWD/.build/cache"`. Replace it with the coordinator's verified command. No other active build instruction repeats that flag.

## Spec

- **Should-fix — `Frisket/FrisketApp.swift:93`:** successful clipboard delivery removes the panel even when History persistence failed. That suppresses the visible History-failure notice the spec requires.
- **Should-fix — `Sources/FrisketCore/CaptureLifecycleCoordinator.swift:60`, `Frisket/ThumbnailPanel.swift:40`:** when Copy commits but clipboard delivery fails, "Delete Capture" reports success and closes the panel, but keeps the History row and image. Either delete them correctly, or change the available action and its wording.

These are verified:

- durable file-first ordering, the migration preflight, dependency confinement and pins, closed diagnostics, and lazy `.noindex` storage with backup exclusion;
- dismiss, focused Esc and Quit all finalize, and Copy retry preserves revision identity;
- all nine commit points have tests, and thumbnails are generated after commit and disposable;
- recovery execution is explicitly deferred to ticket 10;
- persisting authorized unedited output is consistent with the restriction on original pixels, and the static guard gives meaningful, documented lexical protection.

`swift build` passed, and 62 tests passed with three skipped, on x86_64 macOS 26.7 (25G229). arm64 was not executed, and Xcode was not rerun.

Verdict: fix-then-merge
