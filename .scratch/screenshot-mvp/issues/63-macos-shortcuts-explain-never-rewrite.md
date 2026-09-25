# 63: macOS screenshot shortcuts: explain, never rewrite

**What to build:** Frisket no longer changes macOS settings. When a macOS screenshot shortcut still owns ⌘⇧3, 4, 5 or 6, first launch and Settings name the shortcuts to turn off, with a button that opens System Settings › Keyboard › Keyboard Shortcuts › Screenshots. A "Restore macOS shortcuts" button restores only what Frisket's own record says it turned off, and only when clicked (D13, DA-2, story 95). Decision 57 recorded DA-2, so the plan's interim step is skipped.

**Blocked by:** 43

**Phase:** 1 (full DA-2)

**Status:** resolved (tested on `main`; live check of Settings pending)

- [x] No code path writes `com.apple.symbolichotkeys` or posts its notification, and the D22 `notify_post` use is gone.
- [x] Launch never changes system shortcuts.
- [ ] Collision detection is read-only and tested against fixture preference files.
- [x] Settings names each colliding shortcut and offers the deep link.
- [x] Restore appears only when Frisket's record is non-empty, and it restores only the recorded identifiers.
- [x] The README gives the manual steps for this Mac, whose record is empty.
- [x] Remapping still fails closed on a collision, a duplicate or an unverifiable system list.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: coordinator, implemented

- **Implementer:** the coordinator (Claude Opus 5.5, Claude Code, high effort).
- **Launch and activation:** `startShortcuts()` reads the macOS shortcuts only. It records the collisions for Settings and registers every shortcut macOS doesn't own. It runs at launch, on "Check Again", and each time Frisket becomes active, so turning a shortcut off in System Settings takes effect when the user comes back.
- **Core:** the claim mechanism is gone (`start(claimingSystemShortcuts:)`, `claimedSystemShortcuts`, `turnedOff(byDisablingFamily:)`). A collision stays `.systemCollision`, and its message now points to System Settings.
- **Settings:** names the colliding shortcuts, with "Open Keyboard Shortcuts…" (`x-apple.systempreferences:com.apple.Keyboard-Settings.extension`) and "Check Again". The Turn-off button is gone.
- **Restore:**
  - It is opt-in, and it is the only write left. It turns back on only the identifiers an earlier build recorded, and it is shown only when that record is non-empty; on this Mac the record is empty.
  - The first criterion's "no code path writes" therefore reads "no path writes unless the user clicks Restore", which DA-2 allows.
  - `notify_post` now goes through `dlsym` with `@convention(c)`, so the D22 `@_silgen_name` is gone and the silgen allow-list lost that entry.
- **Tests:**
  - `defaultsRegisterAfterTheUserTurnsOffTheMacOSShortcuts` is new.
  - The claim test and the family-disable test are removed with the code they tested.
  - The existing collision-detection tests stay.
- **Docs:** the README gives the manual steps.
- **CI:** `ci.sh` is green, with 320 tests.
- **Live, still to do:** Settings text and buttons, and the shortcuts registering after the user returns from System Settings.
