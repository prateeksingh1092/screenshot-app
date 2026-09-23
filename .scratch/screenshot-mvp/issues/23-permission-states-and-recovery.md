# 23: Screen Recording permission states and recovery

**What to build:** Frisket always knows its Screen Recording permission state, never shows an overlay it can't capture from, and gives Prateek a one-step fix when permission is missing.

**Blocked by:** 08

**Status:** resolved (tested on main at `992a511`; manual criteria pending per decision 49)

- [x] Five explicit states: not asked, denied, granted, revoked while running, needs relaunch.
- [x] Permission is checked before any overlay appears.
- [x] A recovery panel offers "Open Privacy & Security" and "Quit & Reopen".
- [x] The menu-bar icon shows when permission is missing.
- [x] Frisket never draws over a pending macOS screen-capture alert.
- [x] Seam 1 tests drive each state through a stand-in; every state is in the manual checklist, including after re-signing.

## Comments

- 2026-09-23, coordinator (Cursor agent): Codex (GPT-6 Astra, high) implemented this ticket and ran the fresh review (verdict fix-then-merge, `.scratch/screenshot-mvp/reviews/23-code-review-codex.md`).
  - One Codex fix pass moved the state policy into the core as `CapturePermissionPolicy`. It also made Quit & Reopen shell-free: `/usr/bin/open -n` with the fixed installed path, started from `applicationWillTerminate`.
  - A Codex session (GPT-6 Astra, high) resolved the integration conflicts with ticket 09. Quit finalizes Pending captures before relaunch, and a persistence failure cancels Quit and clears the reopen intent.
  - The same session narrowed the repository check to allow the Settings open and the helper's `/dev/null` I/O in app code, with regression fixtures, and fixed a stale `Task` access in the merged magnifier.
  - On `main` at `992a511`: 97 tests passed in 14 suites, and the unsigned Xcode build succeeded on x86_64 macOS 26.7 with Xcode 26.5. arm64 was not executed.
  - Manual criteria pending with Prateek, in an isolated account per `docs/manual-checks/23-permission-states.md`:
    - each of the five states;
    - the ordering against the native alert;
    - Quit & Reopen;
    - behaviour after re-signing.
