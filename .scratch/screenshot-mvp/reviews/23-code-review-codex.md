# Ticket 23 — fresh Codex review (GPT-6 Astra, high), 2026-09-23

Fixed point `df23d4e`, snapshot `c79064a`.

## Standards

- **Should-fix — `Frisket/Adapters/ScreenCapturePermissionAdapter.swift:25`:** grant history, relaunch latching and the state transitions live in the platform adapter. The core contains only an enum and a protocol, contrary to the brief's requirement for a deep core module. Move the platform-independent state policy into the core.

## Spec

- **Should-fix — `Frisket/InstalledAppRelaunch.swift:14`:** Quit & Reopen runs `/bin/sh -c`, which directly violates the explicit "no shell" requirement. Fixed paths and quoted arguments don't satisfy it.

These pass:

- Both capture commands check permission before calling their capture sources.
- Area capture waits for shareable content to load before the selection appears.
- The request marker is a bundle-scoped Boolean in `UserDefaults`, outside History.
- The recovery controls, accessibility labels, menu indicator and closed-set diagnostics are all present.
- The isolated-account checklist keeps ticket 08's grant intact and covers re-signing.

Still unverified at runtime: the ordering against a native alert's dismissal, and the permission-transition heuristics. The stand-ins establish the app's ordering, not macOS behaviour.

Validation passed on x86_64 macOS 26.7 (25G229): the Swift suite (68 passed, 3 skipped), the unsigned Xcode build and the diff checks. arm64 and manual runtime checks were not executed.

Verdict: fix-then-merge
