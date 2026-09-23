# 23: Screen Recording permission states and recovery

**What to build:** Frisket always knows its Screen Recording permission state, never shows an overlay it can't capture from, and gives Prateek a one-step fix when permission is missing.

**Blocked by:** 08

**Status:** in-progress (branch `ticket/23-permission-states-and-recovery`)

- [ ] Five explicit states: not asked, denied, granted, revoked while running, needs relaunch.
- [ ] Permission is checked before any overlay appears.
- [ ] A recovery panel offers "Open Privacy & Security" and "Quit & Reopen".
- [ ] The menu-bar icon shows when permission is missing.
- [ ] Frisket never draws over a pending macOS screen-capture alert.
- [ ] Seam 1 tests drive each state through a stand-in; every state is in the manual checklist, including after re-signing.

## Comments
