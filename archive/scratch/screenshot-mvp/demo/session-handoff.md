# Session handoff — Frisket demo, 2026-09-24

Written so a later session can continue without this chat. The finished film is local and untracked. The script, fixture, note, and Remotion source are on `main`.

## Result

- File: `.scratch/screenshot-mvp/demo/frisket.mp4`
- Length: 73.45 seconds
- Picture: 1920×1080 H.264. Sound: AAC. About 9.5 MB.
- It is a voice walkover on a real screen recording of `/Users/16intelmac/Applications/Frisket.app` (`io.github.prateeksingh1092.frisket.debug`). The interface is not generated.
- Voice is macOS Samantha. Lines are in `script.md`. What is on screen is in `what-it-shows.md`.
- Commit: `e8108ae` on local `main`. Not pushed. The mp4 is gitignored.

Reviewed frames at 1.5s, 8s, 24s, 33s, 48s, 60s, and 68s. No personal names, messages, photos, or documents. The desktop behind the window is the lake wallpaper. Menu-bar icons are system and utility symbols.

## What each part of the film shows

1. The Northline fixture. The `$48` sits on `tok_demo_hide_me`. The “Add to bag” button is clipped.
2. Command-Shift-4. Size badge and the grid labeled “Pixels under the pointer.” The grid is a frozen sample taken before the dimmer.
3. Editor. A black bar crosses the title. A small arrow sits on the price. Crop is the active tool in the later editor frame. The line spoken is “A black bar. An arrow on the price. Cropped to the point.” The token is still partly visible. Do not claim it was fully covered.
4. Command-Shift-5. The thumbnail is the browser window.
5. Command-Shift-6. The selection reads 624×540 and covers the paragraph and the sections under it. The loupe is in the corner.
6. Copy Text. An alert reads “Copied 600 characters.” History is open behind it.
7. The menu-bar menu lists Capture Area ⌘⇧4, Capture Window ⌘⇧5, Capture Full Screen ⌘⇧3, Capture Scrolling Page ⌘⇧6, Focus Latest Thumbnail ⌘⇧2, and History ⌘⇧1.

Captions are the spoken lines, set in Georgia at the lower left. They overlap the page text. There is no music.

## Left out on purpose

A TextEdit paste was recorded and discarded. TextEdit’s open panel sidebar showed the account name. That clip is not in `frisket.mp4` and must not be reused. The words-copied beat is the “Copied 600 characters” alert instead.

## How the recording was driven

- Screen: built-in display only. `ffmpeg` avfoundation device `4` (“Capture screen 0”) is 3584×2240. Device `5` is the ASUS MB166C at x=1792 and was not recorded.
- The installed binary was already current with this tree (no Swift file newer than the binary). It was not rebuilt.
- CleanShot was not running.
- During the take, desktop icons were hidden, the Dock was set to auto-hide, and Brave, Cursor, and cmux were hidden. Safari windows other than the fixture were miniaturized. History was moved aside to `/tmp/frisket-history-backup` and put back afterward. CreateDesktop and Dock autohide were restored to unset. Frisket was relaunched. That restore already ran.
- Fixture: `python3 -m http.server 8765` from `fixture/`, opened in Safari at `http://127.0.0.1:8765/`. The server was stopped.
- Carbon hotkeys do not fire from System Events keystrokes. Post `CGEvent` keyboard events to the HID tap. From `osascript -l JavaScript` those clicks also land. Mouse clicks posted by the `swift` binary do not land.
- The area and scrolling overlays do not take a synthetic mouse-down. Place the rect with arrow keys, then Return. After Shift-arrows, send a flags-changed event with flags 0. If Shift stays down, later nudges resize instead of move.
- Thumbnail buttons are not System Events buttons. The window is named “Pending capture.” Edit is about 57% across and 68% down. Copy Text is about 84% across, same row. Close is about 78% across and 80% down. Thumbnails auto-dismiss in 10 seconds unless the editor has the card marked busy.
- Editor tool buttons are not direct children of the window for System Events. With “Edit Capture” key, the tool keys are r, a, and c. Done is a button named Done.
- Default selection rect, in points, is centered: x 736, y 470, 320×180, on the 1792×1120 built-in display at scale 2. The size badge is in points.

## Remotion

- Project: `.scratch/screenshot-mvp/demo/film`, Remotion 4.0.527, scaffolded with `create-video@4.0.527`. The skill cache on this Mac was 4.0.524. The older Remotion apps in other repos were not upgraded.
- Master recording: `film/public/take.mp4` (gitignored). Voice files: `film/public/v1.m4a` through `v8.m4a` (gitignored).
- Render: `npx remotion render MyComp` from `film/`. Composition id `MyComp`. 2202 frames. Output is the mp4 above.
- Re-render needs those public media files, which are only on this Mac.

## Machine when this note was written

Desktop icons are showing. Dock auto-hide is unset. Frisket is running with the previous History restored. The fixture server is stopped. The user asked for the Mac to shut down after this handoff was saved.
