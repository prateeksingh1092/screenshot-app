# 12: Drag to Finder and to the Trash

Set up as in [README.md](README.md). The harness checks a cancelled drag
(`drag-cancel`). This file checks accepted and refused drops.

1. Run `.build/FrisketTestPattern --show`. Press ⌘⇧4, then Return.
2. Drag the Thumbnail's picture into a Finder folder. The drop is a copy, named
   like `Frisket 2026-09-25 at 14.03.07.png`. Check it:
   `.build/FrisketTestPattern --verify "<dropped file>" 2` (use `1` on a 1×
   display). The capture is now in History, and History's own image under
   `~/Library/Application Support/io.github.prateeksingh1092.frisket.debug/History.noindex/images/`
   is a different file that stays put.
3. Capture again and drag the Thumbnail onto the Trash. If the Trash refuses,
   the Thumbnail stays pending and History gains no row. If it takes a copy,
   the capture is finalized once and History's image stays.
4. After either drop, `History.noindex` has no `staging/` folder.
