# 18: Selection overlay across displays

**What to build:** area selection shows a crosshair on every display, keeps each selection on the display where it started, and survives display and Space changes.

**Blocked by:** 08

**Status:** resolved (tested on `main` at `1c4aaea`; display/Space manual checks pending)

- [x] A crosshair appears on every connected display, including over full-screen apps and after Space switches.
- [x] A selection is confined to its origin display (decision 33), including a display at negative coordinates.
- [x] Unplugging a display mid-selection cancels cleanly with nothing kept.
- [ ] Manual checklist cases on the built-in Retina plus the external 1x display.

## Comments

### 2026-09-23 — coordinator: resolved

Batch-integrated with ticket 11. Codex review then fix (Space tracking). 116 tests passed. Manual: Retina + 1× display cases.
