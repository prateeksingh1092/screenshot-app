# 14: Thumbnail outcomes on quit, display, and lock events; auto-dismiss setting

**What to build:** thumbnails behave predictably when the app quits, a display is unplugged, the screen locks, or the app crashes, and Prateek can set auto-dismiss to a delay or to never.

**Blocked by:** 11, 13

**Status:** ready-for-agent

- [ ] Quit finalizes unedited thumbnails to History, waiting only for commits the user has authorized.
- [ ] Unplugging a display moves its thumbnails to a remaining display.
- [ ] Screen lock leaves thumbnails pending.
- [ ] A crash loses unedited captures; nothing reaches disk before the user acts (decision 31).
- [ ] Settings offers auto-dismiss delays and "never".
- [ ] Each outcome is covered by a seam 1 test; display unplug and lock are also in the manual checklist.

## Comments
