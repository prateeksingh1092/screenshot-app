# 101: Small fixes from the 2026-09-25 design audit

**Blocked by:** none. **Status:** ready-for-agent (medium effort).

- [x] Window-capture failures get their own notice text instead of the "smaller area" wording (`Notices.swift:73-74`).
- [x] The area overlay announces its badge words to VoiceOver, as the window overlay does (`WindowSelectionOverlay.swift:83`).
- [x] A History error message clears when the selection changes (`HistoryWindow.swift:17-52`).
- [x] Settings: Default is disabled when a row is already at its default; a menu item reopens onboarding (`ShortcutSettings.swift:158`, `FrisketApp.swift:148`).
- [ ] The label corner handle scales the label size (audit item 7), as one undo step. <!-- deferred until ticket 97 merges -->

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62). Scope: the first four criteria; the fifth (label corner handle) is deferred until ticket 97 merges, because ticket 97 is changing `EditorWindow.swift` and `MarkEditing.swift`. Recorded as this ticket's decision in `decisions.md`.

- **Window notice:** `Notice.after` returns the new `Notice.windowCaptureUnavailable` ("Window not captured. Frisket could not capture the window. Try again, or capture an area instead.") for a `.captureWindow` that fails as `.unavailable` or `.emptyImage`. Test: `NoticeTests.aFailedWindowCaptureNeverSuggestsASmallerArea`.
- **Badge words for VoiceOver:** the quiet word moved into the core as `SelectionGeometry.Modifiers.badgeWord` (test `SelectionGeometryTests.theBadgeNamesOneModifierAtATime`). `SelectionOverlay` posts it as an announcement when it appears or changes. The posting is AppKit-only, so it has no package test.
- **History errors:** `HistoryWindowModel.selected` clears a row's error on change, unless History itself has failed. App-only model, no package seam; checked by reading.
- **Default:** `ShortcutCommands.isAtDefault` (test `aRowIsAtItsDefaultUntilTheUserChangesIt`) drives `.disabled` on the Default button.
- **Reopen onboarding:** status menu item "What Frisket Stores…" (the onboarding title) calls `LaunchSurfaces.presentOnboardingIfNeeded(requested: true)`; `FirstLaunch.surface(requested:)` shows it even when complete, never over a system alert (test `theMenuReopensOnboardingAfterItWasCompleted`).

Tests were red first (the missing API did not compile), then green. **Open:** the onboarding Later button's VoiceOver label says "show it again on the next launch", which isn't true when a completed onboarding is reopened. The VoiceOver announcement and the menu item need a live look.
