# 101: Small fixes from the 2026-09-25 design audit

**Blocked by:** none. **Status:** ready-for-agent (medium effort).

- [ ] Window-capture failures get their own notice text instead of the "smaller area" wording (`Notices.swift:73-74`).
- [ ] The area overlay announces its badge words to VoiceOver, as the window overlay does (`WindowSelectionOverlay.swift:83`).
- [ ] A History error message clears when the selection changes (`HistoryWindow.swift:17-52`).
- [ ] Settings: Default is disabled when a row is already at its default; a menu item reopens onboarding (`ShortcutSettings.swift:158`, `FrisketApp.swift:148`).
- [ ] The label corner handle scales the label size (audit item 7), as one undo step.
