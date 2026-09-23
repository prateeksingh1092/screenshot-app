# 31 — Copy, Save, and drag from the editor

Automated seam 1 covers editor Copy, Save, and drag of the rendered revision,
plus a failed copy that stays retryable. These checks need the signed app.

1. Capture, open the editor, redact. Press **⌘C**. Confirm the clipboard is
   the redacted image and the thumbnail shows the rendered revision.
2. Capture, redact, **⌘S**. Confirm the saved PNG is the redacted image.
3. Capture, redact, drag from **Drag the edited capture**. Confirm the dropped
   file matches the canvas.
4. If Copy fails, Retry Copy on the thumbnail delivers the same rendered
   revision. VoiceOver names Copy, Save, and the drag well.
