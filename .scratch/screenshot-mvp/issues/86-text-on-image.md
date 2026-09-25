# 86: Text typed on the image

**What to build:** A label is typed directly on the image, with a caret and a box, in the pinned CoreText font. The user picks a size from a menu and a style from Standard, Outlined and Box, and sets the width with a side handle (story 104). The toolbar text field goes away.

**Blocked by:** 84

**Phase:** 2b (decision 59)

**Status:** ready-for-agent

- [ ] Typing `v2.1 $4.99 -10%` renders exactly those characters.
- [ ] Return ends editing without triggering Done, and Esc cancels an empty label.
- [ ] Size and style menus are in the Text tool's contextual controls, and the width handle wraps text.
- [ ] The saved output equals the preview (the parity test from ticket 68).

## Comments

### 2026-09-25: coordinator, created

From decision 59 (Prateek agreed with the CleanShot editor study). Claude Opus 5.5, Claude Code, high effort.
