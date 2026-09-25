# Ticket 39: first recorded manual run (Prateek)

The scripted, pixel-free record plus the bundled synthetic pattern. Hardware
steps stay with Prateek. Never capture real content. On this Intel Mac record
**arm64 not executed**. Keep run JSON under ignored `.build/first-run/`.

The bundled helper is `Tools/FrisketTestPattern.swift`. `--show` covers the
current display and centres a **320×180-point** sRGB pattern (red/green over
blue/white, black marker). `--verify PATH SCALE` checks those dimensions and
marker pixels. Compile, do not launch, until the operator is ready:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -target x86_64-apple-macos26.0 \
  -module-cache-path "$PWD/.build/module-cache" \
  Tools/FrisketTestPattern.swift -o .build/FrisketTestPattern
```

Start a record (metadata only; no launch or capture):

```sh
FRISKET_PERMISSION=granted sh scripts/first-run-record.sh
```

Mark a closed case, then finish only when none remain pending:

```sh
/usr/bin/python3 -B Tools/FirstRun/record.py case \
  --record .build/first-run/record.json --id esc-without-activation --result pass
/usr/bin/python3 -B Tools/FirstRun/record.py finish \
  --record .build/first-run/record.json
```

Allowed results: `pass`, `fail`, `pending`, `not-reproducible`, `blocked`.
No free-text notes. The writer refuses PNG/JPEG/GIF bytes and serial numbers.

## Cases

Use the signed install in [app-build.md](../app-build.md). Capture only the
synthetic helper (decisions 50 and 51). Detailed steps live in the linked
checklists; this file is the recorded index.

| Record id | Runbook |
| --- | --- |
| `pattern-dimensions-and-markers` | [08](08-first-launch.md) steps 3–6 (`--verify`) |
| `screen-recording-not-asked` | [23](23-permission-states.md) §3 |
| `screen-recording-denied` | [23](23-permission-states.md) §4 |
| `screen-recording-granted` | [23](23-permission-states.md) §1 |
| `screen-recording-revoked-while-running` | [23](23-permission-states.md) §6 |
| `screen-recording-after-resign` | [23](23-permission-states.md) §2 |
| `screen-recording-needs-relaunch` | [23](23-permission-states.md) §5 |
| `grant-survives-rebuild-1` | [08](08-first-launch.md) step 7, first rebuild |
| `grant-survives-rebuild-2` | [08](08-first-launch.md) step 7, second rebuild |
| `display-built-in-retina` | [18](18-selection-overlay-displays.md) step 2, `--verify` scale 2 |
| `display-external-1x` | [18](18-selection-overlay-displays.md) step 2, `--verify` scale 1 |
| `display-negative-coordinates` | [18](18-selection-overlay-displays.md) step 4 |
| `unplug-mid-selection` | [18](18-selection-overlay-displays.md) step 5 |
| `overlay-over-fullscreen` | [18](18-selection-overlay-displays.md) step 6 |
| `overlay-across-space-switch` | [18](18-selection-overlay-displays.md) step 7 |
| `esc-without-activation` | [08](08-first-launch.md) step 5 |
| `full-keyboard-access-thumbnails` | [32](32-keyboard-and-voiceover.md) step 3 |
| `voiceover-thumbnails` | [32](32-keyboard-and-voiceover.md) step 4 |
| `default-shortcut-area` | [24](24-shortcuts.md) step 2 (⌃⌥⌘4) |
| `default-shortcut-full-screen` | [24](24-shortcuts.md) step 3 (⌃⌥⌘3) |
| `default-shortcut-focus-thumbnails` | [24](24-shortcuts.md) step 4 (⌃⌥⌘T) |

Window capture is menu-only; it is not a default shortcut.
Mark a case `blocked` when the hardware (second display, fresh TCC account)
is absent rather than inventing a pass.

Offline check: `/usr/bin/python3 -B -m unittest discover -s Tools/FirstRun -p 'test_*.py'`.
