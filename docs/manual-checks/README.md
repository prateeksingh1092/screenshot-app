# Manual checks

These are the checks a person must run. The live harness runs the rest.

## What the harness already checks

`Tools/LiveHarness/beta-matrix.sh` drives the installed app on each display and
checks every row of `Tools/LiveHarness/matrix.tsv`:

- area, window and full-screen pixels (`area`, `window`, `full`);
- a click inside the Selection, and a Selection from the top pixel row
  (`area-click-inside`, `top-row`);
- the editor: arrow and label placement, label text, Solid redaction under
  Blur and Magnify, crop size, Done, Copy and Save on screen
  (`editor-arrow-label`, `editor-label-text`, `editor-redaction`,
  `editor-crop`, `editor-finish-visible`);
- Copy Text with and without text (`copytext-text`, `copytext-none`);
- the Thumbnail stack, ⌘⇧2 focus, the picture's name, and Save's notice
  (`stack`, `focus-latest`, `thumbnail-picture`, `save-confirms`);
- History Copy, Save, Delete and the display it opens on (`history-copy`,
  `history-save`, `history-delete`, `history-display`);
- Settings' display, focus and ⌘⇧ order (`settings-focus`);
- the Latest menu items, and a cancelled editor drag (`menu-latest`,
  `drag-cancel`).

Don't repeat those by hand. A check below is here because the harness can't do
it: it needs a person's judgement, VoiceOver, a trackpad, a second display
unplugged, a locked screen, a fresh macOS account, or a signed rebuild.

## Before any check

- Use the signed, installed app (`~/Applications/Frisket.app`), built as in
  [app-build.md](../app-build.md). Never launch the unsigned build.
- Capture only the synthetic pattern. Hide personal menu-bar items,
  notifications and windows. Keep no capture in the repository.
- Don't reset TCC or change the signing identity on Prateek's account.
- Record: date, `sw_vers`, `uname -m`, `git rev-parse HEAD`, the code
  signature, the display layout (IDs, frames, scales) and the Screen Recording
  state. On this Intel Mac, record **arm64 not executed**.
- A user test lasts 15 minutes at most (decision 66). At the limit, record what
  passed and what is still open.

Build the pattern helper once:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -target "$(uname -m)-apple-macos26.0" \
  -module-cache-path "$PWD/.build/module-cache" \
  Tools/FrisketTestPattern.swift -o .build/FrisketTestPattern
```

| Mode | What it shows |
|---|---|
| `--show` | The current display, with a 320 × 180-point pattern in the centre |
| `--show-all` | Every display |
| `--show-full-screen` | The pattern in its own full-screen Space |
| `--show-window` | Two overlapping, movable pattern windows |

`--verify PATH SCALE`, `--verify-full PATH W H SCALE` and
`--verify-redacted PATH SCALE [colour]` check a saved image.

## The checks

| File | What a person checks |
|---|---|
| [08](08-first-launch.md) | First launch, the permission grant, and two signed rebuilds |
| [11](11-save-and-settings.md) | The export folder: choosing, refusing, iCloud |
| [12](12-drag-handoff.md) | Dropping on Finder and on the Trash |
| [13](13-thumbnail-stack.md) | Placement, swipe, exits, Spaces, two displays |
| [14](14-thumbnail-system-events.md) | Quit, lock, unplug, auto-dismiss |
| [15](15-history-window.md) | History drag, Restore, keyboard, VoiceOver |
| [16](16-retention-and-quota.md) | History limits in Settings |
| [17](17-history-database-failure.md) | A broken History database |
| [18](18-selection-overlay-displays.md) | Selection across displays and Spaces |
| [19](19-selection-precision.md) | Selection modifiers and keys |
| [20](20-full-screen-capture.md) | Full screen with unusual layouts |
| [21](21-window-capture.md) | Window picking edge cases |
| [22](22-capture-exclusion-list.md) | The Capture exclusion list |
| [23](23-permission-states.md) | Every Screen Recording state |
| [24](24-shortcuts.md) | Shortcuts and collisions with macOS |
| [25](25-onboarding-and-about.md) | Onboarding and About |
| [26](26-editor.md) | The editor: keyboard, VoiceOver, close and quit |
| [32](32-keyboard-and-voiceover.md) | Thumbnails by keyboard and VoiceOver |
| [37](37-performance-baselines.md), [38](38-frisket-performance.md) | Performance runbooks |
| [39](39-first-run.md) | The recorded first run (index of cases) |
