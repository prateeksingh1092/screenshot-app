# 20: Full screen with unusual layouts

Set up as in [README.md](README.md). Full-screen capture takes a whole display,
so ask Prateek first and make sure only synthetic content shows. The harness
checks the pixels of each display in the normal layout (`full`).

1. Put the external display left of, then below, the built-in one. Restart
   `.build/FrisketTestPattern --show-all` after each change.
2. With the pointer on the external display, press ⌘⇧3. Copy the Thumbnail,
   save it from Preview (File › New from Clipboard) under `.build/`, and run
   `.build/FrisketTestPattern --verify-full <file> W H 1` with the display's
   pixel size. No shifted crop, padding or clipping.
3. Capture again while an earlier Thumbnail is on screen. The earlier
   Thumbnail is not in the new image.
