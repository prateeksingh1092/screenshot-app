# 30 — Editor close, quit, and logout

Automated seam 1 covers unchanged close → History, Delete capture → discard,
and logout-during-prompt → discard. These checks need the signed app.

1. Capture, open the editor, add no edits, close. Confirm the capture is in
   History and the thumbnail is gone.
2. Capture, redact, close. Confirm the sheet offers **Finalize** (Return,
   default), **Delete Capture** (not default), and **Cancel** (Esc). Cancel
   keeps the editor. Finalize keeps the redacted image. Delete writes nothing.
3. Open an editor and choose Quit. Confirm the same sheet appears. Sudden
   termination stays disabled while the editor is open.
4. Logout or restart with that sheet unanswered discards the pending capture
   (decision 30). Do not use a real logout during unattended work.
