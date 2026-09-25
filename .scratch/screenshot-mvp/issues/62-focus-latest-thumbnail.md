# 62: ⌘⇧2 gives keyboard focus to the latest Thumbnail

**What to build:** ⌘⇧2 gives the latest Thumbnail keyboard focus with a visible focus ring, so arrow keys and single-key actions work at once. Esc hands focus back to the app that had it (D12, story 94).

**Blocked by:** 48

**Phase:** 1

**Status:** resolved in code (tested on `main`); every criterion needs the live row after an approved install

- [ ] After ⌘⇧2, action keys reach the Thumbnail, not the frontmost app.
- [ ] The focused Thumbnail shows a visible focus ring, and VoiceOver focus follows it.
- [ ] Esc returns keyboard focus to the previous app.
- [ ] The ⌘⇧2 row of the live matrix passes.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: coordinator, implemented

- **Implementer:** the coordinator (Claude Opus 5.5, Claude Code, high effort).
- **Cause:** the Thumbnail panel was `.borderless` only. `makeKeyAndOrderFront` on a panel of an inactive app moves accessibility focus but not keyboard input, so keys went to the frontmost app.
- **Fix:**
  - The panel is `.borderless` + `.nonactivatingPanel`, with `becomesKeyOnlyIfNeeded = false`. ⌘⇧2's `focus()` now gives it real key status without activating Frisket, and the previous app stays active.
  - The card draws a 3 pt accent-colour ring while the panel is key (`ThumbnailModel.keyFocused`). The ring is hidden from VoiceOver, which already follows the panel.
- **Tests:** there is no package seam for key status. `ci.sh` is green: 327 tests, and the unsigned build succeeds.
- **Live:** the `focus-latest` row now expects pass (C after ⌘⇧2 copies). Two more checks are to be added at that run: Esc hands keys back to the previous app, and the ring is visible.
