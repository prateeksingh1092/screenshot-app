# 63: macOS screenshot shortcuts: explain, never rewrite

**What to build:** Frisket no longer changes macOS settings. When a macOS screenshot shortcut still owns ⌘⇧3, 4, 5 or 6, first launch and Settings name the shortcuts to turn off, with a button that opens System Settings › Keyboard › Keyboard Shortcuts › Screenshots. A "Restore macOS shortcuts" button restores only what Frisket's own record says it turned off, and only when clicked (D13, DA-2, story 95). Decision 57 recorded DA-2, so the plan's interim step is skipped.

**Blocked by:** 43

**Phase:** 1 (full DA-2)

**Status:** ready-for-agent

- [ ] No code path writes `com.apple.symbolichotkeys` or posts its notification, and the D22 `notify_post` use is gone.
- [ ] Launch never changes system shortcuts.
- [ ] Collision detection is read-only and tested against fixture preference files.
- [ ] Settings names each colliding shortcut and offers the deep link.
- [ ] Restore appears only when Frisket's record is non-empty, and it restores only the recorded identifiers.
- [ ] The README gives the manual steps for this Mac, whose record is empty.
- [ ] Remapping still fails closed on a collision, a duplicate or an unverifiable system list.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
