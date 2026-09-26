# 103: A dead menu item and a dead permission button (D33, D34)

**What Prateek saw (2026-09-25, acceptance test 83, test 11, build `4969168`):**
- **D33:** after the external display was unplugged, its Thumbnail moved to the main display and then left. The menu's **Focus Latest Thumbnail** stayed enabled with no Thumbnail on screen, and clicking it did nothing. Copy Latest and Delete Latest are disabled correctly (decision 79).
- **D34:** after Screen Recording was revoked in System Settings, capture showed the permission message. Its **Request Screen Recording** button did nothing. Once the user has answered, macOS doesn't prompt again, so a second request is silent.

**Status:** ready-for-agent (medium effort)

- [x] Focus Latest Thumbnail is disabled whenever `thumbnails()` is empty, by the same rule as Copy Latest. Add a test at that seam, and extend the live `menu-latest` row.
- [x] Remove the "Request Screen Recording" button from the permission message (decision 100). The existing "Open System Settings" button, which already opens the Screen & System Audio Recording page, stays. Add a test on the permission-recovery state (see `docs/permission-recovery.md`).
- [x] The permission message text matches the button: after a refusal, it tells the user to turn Frisket on in System Settings and relaunch if asked.

## Comments

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62).

- **D33:** `Thumbnails.latestToFocus` (the newest card, Copy Latest's rule) joins `latestToCopy` and `latestToDelete`. The menu's `validateMenuItem` now disables Focus Latest Thumbnail through `CaptureSurfaces.canFocusLatest`, the same check as Copy Latest. Test: `ThumbnailStackCommandsTests.focusLatestActsOnlyWhenAThumbnailIsShown` (no Thumbnail, one Thumbnail, then the card exits). The live `menu-latest` row now also requires Focus Latest Thumbnail to be disabled (matrix defects `D17,D33`); not run.
- **D34:** new `PermissionRecoveryContent` in FrisketCore holds the message and buttons per `CapturePermissionState`; `PermissionRecoveryPanel` shows it. Denied, revoked and needs-relaunch have no Request button; their message says to turn Frisket on in System Settings › Privacy & Security › Screen & System Audio Recording and to quit and reopen if macOS asks. The not-asked state keeps Request, because it is the only way to raise the first macOS alert (this ticket's decision). "Open Privacy & Security" is renamed "Open System Settings", decision 100's name; it opens the same page. Tests: `PermissionRecoveryContentTests` (4 tests).
- Docs: `docs/permission-recovery.md`, `docs/manual-checks/23-permission-states.md`, spec story 23.
- Red → green: both new tests failed to compile before the change (missing API), and pass after. No knownDefect wrapper existed for D33 or D34.
- Open: live `menu-latest` row and a live look at denied recovery (manual check 23, step 4).
