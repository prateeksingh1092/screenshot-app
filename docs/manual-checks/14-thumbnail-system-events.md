# 14: Quit, lock, unplug and auto-dismiss

Set up as in [README.md](README.md). None of this is in the harness.

1. **Quit.** Take two captures. Quit Frisket from its menu. Relaunch. Both are
   in History; no Thumbnail is left.
2. **Lock.** Take one capture and lock the Mac at once. Unlock after more than
   10 seconds. The Thumbnail is still pending. It leaves once the rest of its
   time has passed.
3. **Unplug.** With a second display, capture on it, then unplug it. The
   Thumbnail moves to the other display and stays pending.
4. **Auto-dismiss.** In Settings › Thumbnails, set 0 seconds: a new capture is
   kept in History at once. Set **Never auto-dismiss**: a capture stays well
   past 10 seconds, and a fifth capture still pushes the oldest into History.
   Relaunch: Never is kept. Set 10 seconds again.
5. **Logout.** Only in a test account: log out with an edited capture open in
   the editor and its close confirmation unanswered. The capture is discarded
   (decision 30). Never log out of Prateek's account for this.
