# Next session prompt — Frisket feature demo

Paste this whole document as the task. Do the video. Do not stop after a plan.

---

You are making a short product demo of Frisket, the menu-bar screenshot app in this repo. The installed app is `/Users/16intelmac/Applications/Frisket.app` (bundle id `io.github.prateeksingh1092.frisket.debug`). Rebuild and reinstall from this tree if that binary is older than `main`.

The video has to make someone feel why they would reach for Frisket instead of the macOS screenshot tool. It is a voice walkover on a real screen recording of the real app. It is not a manual, not a feature matrix, and not an AI-generated fake of the interface. Every shot of Frisket must be the actual app.

## What “connects” means

Open on a moment, not a menu. Someone is looking at a page, sees the thing they need, and takes it in one press. The shortcuts are the rhythm of the film. Name a key only when the finger would hit it.

Aim for 70–100 seconds. If a feature does not change the feeling of that minute, leave it out of the narration and do not linger. Coverage still has to include the captures, the thumbnail, the editor, text copy, and History, because those are the product. Settings, onboarding, About, and the exclusion list get at most one glance, or they stay out.

Write the voice script before you record. Short sentences. Sound like a person showing a friend, not a trainer reading steps. Record the voice after the picture is cut, or to a locked script while you perform, then mix. The voice must match what is on screen. No claims the picture does not show.

## Do not touch private data

Before recording, make a clean stage:

- Quit CleanShot if it is running. It owns the same Command–Shift number keys.
- Close or hide Mail, Messages, browsers with real tabs, calendars, photos, and anything with account names. A menu bar full of personal apps is private data.
- Use a new desktop Space if that is the cleanest way to hide the rest.
- All pages, images, and documents in the shot are ones you create or download for this demo. No iCloud folders, no `~/Documents` personal files, no existing History items that you did not just capture from the fixture.
- Review the finished frames before you keep the file. If a personal name, photo, or message appears, cut it or reshoot. Do not commit the mp4 if that review is uncertain. Commit the script, the fixture page, and a note of what the video shows.

## Build the stage yourself

Make a local HTML page and open it in the browser. It should look like a small product page a person would actually screenshot:

- A headline and a price.
- A short paragraph worth copying as text.
- A deliberate visual bug or callout (a broken button, a misaligned price, a token that should be hidden).
- A long section below the fold so scrolling capture has something to walk.
- No third-party trackers. `file://` or a local static server is enough.

You may download a clearly free texture, font, or sample photo for that page. You may open other non-personal local apps (TextEdit, a calculator, a second window of the fixture) when a window capture needs a target. You may generate a simple hero image. Do not generate a fake Frisket window and pretend it is the app.

The area-capture loupe is labeled **Pixels under the pointer**. If you show it, say what it is in one line: it is a frozen grid of the pixels under the cursor, taken before the dimmer, so the border is not in the sample. The desktop behind the dimmer is still live. Do not call it a review.

## What the app actually does

Use these keys. They are the defaults:

| Keys | Action |
| --- | --- |
| ⌘⇧4 | Area. Drag, or Return for the centered rectangle. Esc cancels. The badge is the size. |
| ⌘⇧5 | Window. Hover or arrows, Return, Esc. |
| ⌘⇧3 | Full screen of the display under the pointer. |
| ⌘⇧6 | Scrolling. Select a region first, then move the page. Done or Cancel. |
| ⌘⇧2 | Focus the latest thumbnail. |
| ⌘⇧1 | History. |

After a capture, a thumbnail appears. Copy, Save, Edit, Copy recognized text, Delete, or Close. Close, Esc, or a sideways swipe keeps it in History. Copy removes the card when it succeeds.

The editor tools are Solid redaction, Crop, Arrow, Shape, Text, Blur, and Magnify. Undo is ⌘Z. Redaction is solid black and stays black under blur. Text is letters and digits from a bitmap font, larger than it used to be, not a full typeface. Arrows have a head. While dragging, the canvas previews the tool (a line, the words, or a dimmed outside for crop). There is no color picker and no way to move a mark after it is drawn. Do not imply those exist.

History keeps finalized shots locally (30 days or 1 GB). Save writes a PNG outside History, by default in `~/Pictures/Frisket`. Nothing in this demo uploads.

## A shape that works

Use this spine unless a better one appears while you rehearse. Keep it one story.

1. The page is on screen. One sentence of the problem: you need this, not the whole desktop.
2. ⌘⇧4. Show the size and, briefly, the loupe. Take the broken control. Thumbnail. Edit.
3. In the editor, redact a fake secret, point an arrow at the bug, crop to the point. Done.
4. ⌘⇧5 on the browser window, as the “send the whole window” beat.
5. ⌘⇧6 down the long section, a few seconds, not a tutorial of the grabber.
6. Copy recognized text from the paragraph and show it landing in TextEdit.
7. ⌘⇧1. The shots are still there. One line: they stay on this Mac.
8. End on the menu-bar icon and the keys, already proven, not re-listed.

⌘⇧3 can replace or follow the window shot if the stage is clean. If the full screen would include anything personal, skip it.

## How to make the film

- Rehearse each beat once. Then record picture with a real screen capture (`ffmpeg` avfoundation, or another local recorder). Record the voice separately to the script and mix so speech does not fight the clicks.
- Cut dead air. The selection UI can stay long enough to read the size. Do not hold on Settings.
- Music only if it stays under the voice. Silence is better than a stock bed that shouts.
- Export one mp4, 1080p if the display allows, H.264, stereo or mono voice. Put the master and a shot list under `.scratch/screenshot-mvp/demo/` and gitignore the mp4 if you are not sure it is clean. Commit the script and the HTML fixture.
- Play the finished file back yourself and check every feature you narrate is visible. Fix the cut or the line. Do not hand back an unwatched file.

## Tools

Use whatever you already have: the browser, a local page, screen recording, ffmpeg, the system voice or a better local narrator, image generation for fixture art only. The spoken-action-video skill is for a person on camera saying lines while their hands act. This demo is the app on screen with a voice walkover. Do not substitute a generated presenter for the product.

## Done

The session is done when the mp4 exists, you have watched it, the voice matches the picture, no private data is in frame, and the script plus fixture are committed. Say where the file is and how long it runs. Do not describe the video as a user manual.
