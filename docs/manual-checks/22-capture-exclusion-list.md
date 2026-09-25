# 22: The Capture exclusion list

Set up as in [README.md](README.md). The package tests check that area, full
screen and window picking honour the list. This file checks the Settings list
and a real app. The list matches bundle IDs, so use a pattern app that has one;
an unbundled window can't be excluded (decision 69).

1. In Settings › Capture exclusion list, the list starts empty ("No apps
   added."). Add an app; cancel the picker once and nothing changes. Add the
   same app twice: one entry. Its name and bundle ID are readable. Add and
   Remove work by keyboard and VoiceOver.
2. Show that app's window over the pattern. An area capture across it and a
   ⌘⇧5 pick both leave it out. An app not on the list still shows.
3. Relaunch Frisket, and separately quit and reopen the listed app. It is still
   left out.
4. Remove it: it shows again. Frisket's own windows stay left out.
