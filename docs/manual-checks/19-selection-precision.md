# 19: Selection modifiers and keys

Set up as in [README.md](README.md). The package tests check the geometry; the
harness checks the pixels. This file checks how it feels under a real pointer
and keyboard, on a 2× and a 1× display. There is no Loupe (decision 60).

Over `.build/FrisketTestPattern --show`, press ⌘⇧4, then:

1. **Shift** during a drag locks the axis you move along first. Release it and
   free resizing resumes.
2. **Option** during a drag grows the rectangle from its centre. At a display
   edge it stops evenly. Try it with Shift too.
3. **Space** during a drag moves the whole rectangle without resizing it. It
   stops at the display edge. Releasing Space resumes resizing without a jump.
4. **Arrows** before a drag move the default rectangle by one device pixel;
   **Shift-arrows** resize it by one device pixel. It stops at the display
   edge and never shrinks below one pixel. Size and capture it with the
   keyboard only, then Return.
5. A click without a drag captures nothing. The size badge shows the
   Selection's size while dragging.
