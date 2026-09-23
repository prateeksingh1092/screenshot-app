# 17 — History database failure

Automated seam 1 covers corrupt, unknown-migration, and permission-denied
databases: no writes, delivery continues, recover after repair re-enables
History. These checks need the signed app and a real History folder.

1. Quit Frisket. Replace `History.noindex/history.sqlite` with a text file.
   Relaunch. Confirm the "History is off" notice, then Copy and Save a new
   capture. Confirm History stays empty and the sqlite file is still the text
   file.
2. In Settings → History, use **Show History Folder** and **Try Again**.
   Confirm the folder opens and Try Again does not delete the file.
3. Restore or remove the bad sqlite file, Try Again, then dismiss a capture
   and confirm it appears in History.
4. VoiceOver: the notice, Try Again, and Show History Folder are labelled.
