<!-- Provenance: Cursor Claude Opus 5.5 High subagent 2fde8f32-9f18-43df-a854-1a693065d40c, round 1, 2026-09-22. Final response saved verbatim by the facilitator. -->

## macOS UX/UI and accessibility designer: round 1

### Findings

**UX-1: Keyboard/VoiceOver thumbnail promise is unmeetable with a non-activating panel**
- Target: decision 24 (and 4)
- Attack: A keyboard-only or VoiceOver user cannot reach Copy/Save/Drag/Edit on the thumbnail: the panel never becomes key, actions render and shortcuts fire only while the pointer hovers a card, and the open-editor shortcut is off by default. Auto-dismiss can also expire before the user gets there.
- Severity: blocker
- Evidence (observation): `QuickAccessPanel.swift:22` (`.nonactivatingPanel`), `:184` (`canBecomeKey false`); `QuickAccessCardView.swift:74,80` (actions only `if isHovering`); `QuickAccessManager.swift:1003-1011` (shortcuts gated on hover), `:237-238` (editor shortcut off by default).
- Amendment: Add a global "focus thumbnails" shortcut that temporarily makes the panel key; arrows move between cards; C/S/E/Delete/Esc act on the focused card. Expose each card as a VoiceOver element with hover-independent custom actions; announce new captures. Pause auto-dismiss while the stack has keyboard or VoiceOver focus. Checklist: with Full Keyboard Access and VoiceOver on, complete all four actions without a pointer.
- Changes an accepted product decision (1-12): no

**UX-2: Every thumbnail exit silently commits to history, with no discard path**
- Target: decision 5
- Attack: "Dismiss" is the commit, but dismissal is never enumerated. In Snapzy it includes the 10 s timeout, swipe, and an overflow drop of the oldest card when a sixth capture arrives (max 5). A user who accidentally snaps a password screen and waits it out keeps it for 30 days.
- Severity: major
- Evidence (observation): `QuickAccessManager.swift:82,226` (10 s default), `:157,295-298` (max 5, oldest dropped), `:1137` (Snapzy does have an explicit delete).
- Amendment: Spec enumerates every exit path and its outcome: timeout, swipe, close, overflow, Esc, quit, display unplug, screen lock. Add a keyboard-reachable **Delete capture** on the thumbnail that bypasses history. Offer auto-dismiss "never". Fixture test per exit path.
- Changes an accepted product decision (1-12): no (refines 5)

**UX-3: Cmd-Q / logout with an open editor, and close-without-edits, are undefined**
- Target: decision 17 (with 16)
- Attack: Snapzy prompts only on window close and has no termination hook, so Cmd-Q, logout, or restart drop pending captures. Decision 17 is silent on closing with no edits. "Delete capture" is a destructive choice adjacent to Finalize.
- Severity: major
- Evidence (observation): `AnnotateWindowController.swift:537-570` (close-only sheet; Save is first/default); repo-wide search found no `applicationShouldTerminate`.
- Amendment: Finalize = default (Return); Cancel = Esc; Delete capture destructive-styled, never default. Add a termination handler presenting the same sheet per open editor; disable sudden termination while editors exist. Define unanswered-logout outcome (question below). Define close-without-edits (finalize unedited vs delete). Test Cmd-Q with two editors open.
- Changes an accepted product decision (1-12): no

**UX-4: Denied/revoked Screen Recording recovery, worsened by local signing**
- Target: gap (interacts with 21)
- Attack: Screen Recording has awkward states (granted-but-needs-relaunch, denied, revoked mid-session). A locally signed build whose identity changes per rebuild may drop the grant every build (inferred from Snapzy's own comment). The user sees a blank overlay or silent failure.
- Severity: major
- Evidence (observation): `ScreenCaptureManager.swift:183-246` (relaunch-required probe; Settings fallback); `AppIdentityManager.swift:25-28` ("preserve existing macOS capture permissions across rebuilds"), `:114-121`.
- Amendment: Spec onboarding states plus a recovery panel ("Open Privacy & Security", "Quit & Reopen"); menu-bar icon shows a permission-missing state; never show an overlay without permission. Checklist: each state after `tccutil reset ScreenCapture <bundle-id>` and after a rebuild. Signing mechanics outside my role.
- Changes an accepted product decision (1-12): no

**UX-5: Default shortcuts collide with system Cmd-Shift-3/4/5**
- Target: decision 4 (gap: no defaults chosen)
- Attack: Snapzy defaults to Cmd-Shift-3/4/5 and, if it can't read system shortcut settings, assumes no conflict, producing double captures or the system winning.
- Severity: major
- Evidence (observation): `KeyboardShortcutManager.swift:28-54`; `SystemScreenshotShortcutManager.swift:88-93`.
- Amendment: Ship non-colliding defaults, or an explicit onboarding takeover whose detection fails closed ("couldn't verify"). Checklist: with system shortcuts enabled, each default triggers exactly one tool.
- Changes an accepted product decision (1-12): no

**UX-6: Retention and quota eviction are invisible**
- Target: decisions 5, 18
- Attack: Snapzy onboarding never mentions history. Scrolling captures can hit 1 GB early and silently remove items younger than 30 days; decision 18 only shows usage in Settings.
- Severity: major
- Evidence (observation): `SnapzyOnboardingStep.swift:10-14` (no history step); no "history" match in onboarding code.
- Amendment: First-run copy stating the 30-day/1 GB rule and that Save keeps a permanent copy; thumbnail states "Kept in History" (VoiceOver-announced). After quota-driven eviction, a one-time non-modal notice plus a Settings line ("Removed N items on <date> to stay under 1 GB"). Fixture: quota eviction emits a UI-observable event.
- Changes an accepted product decision (1-12): no

**UX-7: Overlay and multi-display behavior lacks acceptance criteria**
- Target: decision 23
- Attack: "Scripted manual checklist" has no pass criteria; Snapzy's overlay is 4,672 lines including workarounds for non-key-display crosshairs, Esc routing, and mid-selection display changes.
- Severity: major
- Evidence (observation): `AreaSelectionWindow.swift:103-110, 237, 250, 735-743, 1025`; `QuickAccessPanel.swift:104` (joins all Spaces incl. full-screen); `QuickAccessPanelController.swift:85-92` (thumbnail follows capture display).
- Amendment: Explicit pass criteria: crosshair on every display; Esc cancels without the app active; mixed-DPI selections confined to the origin display (as Cmd-Shift-4 does, inference); display unplug mid-selection cancels cleanly; device-pixel magnifier; Space-move, Shift-axis, Option-center, arrow-nudge; window highlight excludes the app's own panels; thumbnail appears on the capture display including over full-screen Spaces.
- Changes an accepted product decision (1-12): no

**UX-8: Accessibility scope omits display settings and is untestable**
- Target: decision 24
- Attack: No Increase Contrast, Reduce Transparency, or color-safe annotation defaults (default stroke is red); Snapzy mutes sounds under Reduce Motion.
- Severity: minor
- Evidence (observation): no `increaseContrast` handling anywhere; `AnnotateState.swift:240` (red default); `QuickAccessSound.swift:33-50`; Reduce Motion honored at `QuickAccessStackView.swift:13,36`.
- Amendment: Honor Reduce Motion, Increase Contrast, Reduce Transparency (checklist item each); a default palette distinguishable under protanopia/deuteranopia with named colors in the picker; selection state never color-only; decouple sound from Reduce Motion. Accessibility Inspector audit with zero warnings on thumbnail, editor chrome, Settings, onboarding.
- Changes an accepted product decision (1-12): no

### Keep
- Decision 4: non-activating floating thumbnail with on-demand editor matches CleanShot X and the built-in tool.
- Decision 17: drag finalizes the rendered result; never persist the unredacted original.
- Decision 22: 500 ms thumbnail target, measured against the built-in tool.

### Questions only Prateek can answer
1. Replace macOS's Cmd-Shift-3/4/5, or coexist on different defaults?
2. Should the thumbnail offer a one-step discard that bypasses history, or should every exit save as decision 5 implies?
3. On logout or restart with an open editor and no response, finalize the rendered (redacted) result or discard the capture?
