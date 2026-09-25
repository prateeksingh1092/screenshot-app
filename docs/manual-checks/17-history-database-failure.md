# 17: A broken History database

Set up as in [README.md](README.md). The package tests cover corrupt,
unknown-migration and permission-denied databases. This file checks the app
with a real folder. Back up `History.noindex` first and put it back after.

1. Quit Frisket. Replace `History.noindex/history.sqlite` with a text file.
   Relaunch. A notice says History is off. Copy and Save a new capture: both
   work. History stays empty and the text file is untouched.
2. In Settings › History, **Show History Folder** opens the folder. **Try
   Again** does not delete the file.
3. Put the real database back and press Try Again. Let a capture go to
   History: it appears.
4. VoiceOver reads the notice, Try Again and Show History Folder.
