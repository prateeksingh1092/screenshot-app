# 18: Selection across displays and Spaces

Set up as in [README.md](README.md), with two displays. The harness checks area
pixels and the top pixel row on each display (`area`, `top-row`). This file
checks what needs a display moved, unplugged or a Space switched. Record
"Displays have separate Spaces" too.

1. Run `.build/FrisketTestPattern --show-all`. Press ⌘⇧4 on one display and
   start dragging on the other. The Selection starts on its Origin display and
   stops at that display's edge when you drag across. Do it from each display.
2. In System Settings › Displays, put the external display left of, then below,
   the built-in one. Restart `--show-all` after each change. Repeat step 1 and a
   Return capture on the external display; check it with `--verify <file> 1`.
   No shifted or flipped crop.
3. Start dragging on the external display and unplug it before releasing. All
   overlays close, no Thumbnail appears, and the next Selection works. Repeat
   with the drag on the built-in display. Adding a display or changing a
   resolution during a Selection also cancels it.
4. Run `.build/FrisketTestPattern --show-full-screen` on one display. Press
   ⌘⇧4: the overlay is above the full-screen pattern. Switch Spaces and back
   during the Selection: the overlay stays on top, keeps its rectangle, and Esc
   still cancels.
5. With the helper frontmost, press Esc before a drag, during a drag, and after
   a Space switch. Only the overlays close. Frisket never becomes the active
   app, and the pointer comes back.
