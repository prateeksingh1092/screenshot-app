# 39: The recorded first run

A scripted record of a manual run. It holds metadata and results only, never
pixels. Set up as in [README.md](README.md). Keep the record under ignored
`.build/first-run/`.

Start a record (no launch, no capture):

```sh
FRISKET_PERMISSION=granted sh scripts/first-run-record.sh
```

Mark each case, then finish when none is pending:

```sh
/usr/bin/python3 -B Tools/FirstRun/record.py case \
  --record .build/first-run/record.json --id esc-without-activation --result pass
/usr/bin/python3 -B Tools/FirstRun/record.py finish \
  --record .build/first-run/record.json
```

Results: `pass`, `fail`, `pending`, `not-reproducible`, `blocked`. There are no
free-text notes. The writer refuses image bytes and serial numbers. Mark a case
`blocked` when the hardware or a test account is missing.

## Cases

| Record id | Where | Harness |
|---|---|---|
| `pattern-dimensions-and-markers` | harness row `area` | yes |
| `display-built-in-retina` | harness rows on the built-in display | yes |
| `display-external-1x` | harness rows on the external display | yes |
| `default-shortcut-area` | [24](24-shortcuts.md) step 2 (⌘⇧4) | |
| `default-shortcut-full-screen` | [24](24-shortcuts.md) step 2 (⌘⇧3) | |
| `default-shortcut-focus-thumbnails` | [24](24-shortcuts.md) step 2 (⌘⇧2); harness row `focus-latest` | partly |
| `screen-recording-granted` | [23](23-permission-states.md) step 1 | |
| `screen-recording-after-resign` | [23](23-permission-states.md) step 2 | |
| `screen-recording-not-asked` | [23](23-permission-states.md) step 3 | |
| `screen-recording-denied` | [23](23-permission-states.md) step 4 | |
| `screen-recording-needs-relaunch` | [23](23-permission-states.md) step 5 | |
| `screen-recording-revoked-while-running` | [23](23-permission-states.md) step 6 | |
| `grant-survives-rebuild-1` | [08](08-first-launch.md) step 4, first rebuild | |
| `grant-survives-rebuild-2` | [08](08-first-launch.md) step 4, second rebuild | |
| `esc-without-activation` | [08](08-first-launch.md) step 5 | |
| `display-negative-coordinates` | [18](18-selection-overlay-displays.md) step 2 | |
| `unplug-mid-selection` | [18](18-selection-overlay-displays.md) step 3 | |
| `overlay-over-fullscreen` | [18](18-selection-overlay-displays.md) step 4 | |
| `overlay-across-space-switch` | [18](18-selection-overlay-displays.md) step 4 | |
| `full-keyboard-access-thumbnails` | [32](32-keyboard-and-voiceover.md) step 2 | |
| `voiceover-thumbnails` | [32](32-keyboard-and-voiceover.md) step 3 | |

For a harness case, copy the result from the harness report in
`.build/live-harness/runs/<time>/`.

Offline check: `/usr/bin/python3 -B -m unittest discover -s Tools/FirstRun -p 'test_*.py'`.
