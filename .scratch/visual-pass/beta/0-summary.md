# Live beta summary: 2026-09-24

Frisket 73be4ce, installed at `~/Applications/Frisket.app` (PID 47669, never relaunched). There were two passes:
- **Detached run** (about 18:50–19:05, ASUS only): person 1 and part of person 2. It stopped when the built-in display dropped out and the safety classifier blocked further driving.
- **Main-session run** (about 19:50–20:15, any screen): the rest of person 2, and persons 3 and 4.

Notes: `1-first-run.md`, `2-capture.md`, `3-editor.md`, `4-history.md`. Evidence: `evidence/` (gitignored PNGs).

## Static findings, checked live

| # | Finding | Result |
| --- | --- | --- |
| A | Saved edits misplace arrows and text on images taller than 256 px | **Confirmed.** The preview is correct. The saved and History PNG has the label twice (rows 40 and 296) and no arrow: 731 red ink px in each 256-row band, 0 in the arrow band |
| B | Label glyph loss | **Confirmed.** `v2.1 $4.99 -10%` is drawn as `V21 499 10` on the canvas and in the output |
| C | Return in the label field finalizes | **Refuted.** Nothing happens |
| D | Scrolling fragility and keyboard steal | **Keys: confirmed.** Page Down and Space are eaten while the panel is up. **Fragility: different from predicted.** Flicks and upward scrolls did not discard the capture, but steady scrolling **silently drops rows at seams** (up to 34 rows, including inside content) and a flick **silently truncates** the result below the selected height |
| E | A cancelled drag leaves a staged PNG | **Confirmed, and worse.** A cancelled editor drag also commits the capture to History. The 744-byte edited PNG stays in `staging/drag/` and survives deleting that capture |
| F | ⌘⇧2 doesn't give the card keyboard focus | **Confirmed** (detached run) |
| G | Where surfaces appear | Overlay, cards, editor, scrolling panel and alerts appear on the capture's display. **History and Settings open on the built-in display** at a remembered position, without keyboard focus |
| H | History Delete without confirmation | **Confirmed.** The Delete key and button delete at once. Delete **fails while the capture's card is still open**, with a misleading "Delete failed. Try again." |
| I | Crashes, hangs, memory | None. RSS went from 131 MB to 174 MB over the session, with CPU idle |
| 7 (static) | Pointer on the top pixel row | **Confirmed** (detached run) |
| 3 (static) | macOS shortcuts turned off with no restore | **Confirmed**: all 7 off, no restore record |

## New issues found live, most severe first

1. **Critical: saved edits don't match the preview** (A). The broken image is what is stored in History and copied.
2. **High: window capture (⌘⇧5) is unusable on this Mac.**
   - The picker targets the mouse cursor. ScreenCaptureKit lists the cursor as a window whose owner has an empty-string bundle ID, and `WindowSelection.swift:36` only rejects nil.
   - Clicking goes through to the app underneath. Return shows a misleading "Capture unavailable… smaller area" alert.
3. **High: scrolling capture silently corrupts or truncates content** (D).
4. **High: clicks inside the selection hole go through to the app underneath.**
   - This happens in both area and window mode.
   - The overlay then loses keyboard focus, and only a click on the veil recovers it.
5. **High (UX): the editor's Done, Copy, Save and Close live only in the toolbar's `>>` overflow** at the editor's default width.
6. **Medium: a cancelled drag finalizes the capture and leaves pixels in `staging/drag/`** (E).
7. **Medium: Copy Text on an image with no text wipes the clipboard** (empty string) and shows a modal "Copied 0 characters".
8. **Medium: pending cards overlap** instead of stacking (seen twice).
9. **Medium: History Delete has no confirmation**, and it fails with a misleading message while the capture's card is open.
10. **Medium: the scrolling panel eats Page Down and Space.**
11. **Medium: Settings focus lands in the auto-dismiss field,** and Settings and History open on the other display.
12. **Low–medium (a11y):**
    - A committed card is still announced as "Pending capture", with Edit and Delete actions it no longer has, and its "keep in History" action is a no-op.
    - History rows announce the same label three times.
    - The card picture has no AX element.
13. **Low:**
    - Silent Save with UUID file names.
    - About shows raw Markdown and internal text.
    - Copy/Delete Latest are enabled with nothing pending.
    - Modifier order is inconsistent (⌘⇧ vs ⇧⌘).

## What held up

- Area and full-screen captures are pixel-exact with correct sRGB, including 1920×1080 full screen (`--verify-full` PASS).
- Solid redaction stays exact black under overlapping blur and magnify (`--verify-redacted` PASS).
- The dirty-close sheet is clear, and Cancel and Delete Capture behave correctly. Undo works.
- The clipboard always gets `ConcealedType`. Accessibility labels and help text are thorough.
- The area overlay's modifier keys and badge words behave as specified.

## State left behind

- The clipboard is restored (1 text item).
- The system screenshot hotkeys are unchanged (all 7 off, as found).
- Frisket's defaults are unchanged apart from `screenRecordingPermissionWasRequested = 1`, which Frisket wrote itself.
- No Frisket windows are open, and the pattern tools are stopped.
- History holds 13 images:
  - the 4 pre-existing captures from 18:29–18:32 (untouched);
  - the detached run's test captures;
  - this session's remaining test captures (two of them were deleted as part of the tests).
- `staging/drag/` still holds the 744-byte test PNG (finding E evidence). Frisket's launch sweep should remove it.
- `~/Pictures/Frisket` gained test exports `Frisket-812101E6-…-r1.png` (detached run) and `Frisket-29E0BDAC-…-r2.png` (this run).
- Temporary screenshots in `/tmp/frisket-beta` were deleted. Two window-picker screenshots that showed desktop files were deleted and not described.
- One harness misclick at (900,1030) landed in the terminal hosting this session. It only focused that window.
