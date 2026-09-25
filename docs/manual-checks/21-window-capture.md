# 21: Window picking edge cases

Set up as in [README.md](README.md). The harness checks that ⌘⇧5 captures
exactly a pattern window (`window`). `WindowSelection` tests check the
filtering. This file checks the live cases around it.

Run `.build/FrisketTestPattern --show-window` (two overlapping windows), then
press ⌘⇧5 for each case:

1. **Overlap.** The frontmost window under the pointer is highlighted. Hovering
   the visible part of the rear window picks that one. A click on the desktop
   captures nothing.
2. **Frisket's own panels.** Put a Thumbnail over a pattern window. The
   Thumbnail never highlights, and it is not in the captured window.
3. **Minimized and other Spaces.** A minimized pattern window and one on
   another Space are not offered. Bring them back and they are. Switching
   Spaces during window picking cancels it.
4. **Layouts.** Capture a window on the external display placed left of or
   above the built-in one, and a window spanning both displays. Check each with
   `--verify-full <file> W H SCALE`: no shadow padding, cursor or stretch.
5. **Changes.** Close or minimize the highlighted window before clicking:
   nothing stale is captured. Resize it and pick again: the new size is used.
6. **Keyboard and VoiceOver.** Arrows or Tab move between windows, Return
   captures, Esc cancels without activating Frisket. VoiceOver reads the
   instructions and the highlighted window, without its title.
