# 33 — Copy recognized text

Automated seams cover count-only outcomes, stale-result drop, a canary
stand-in before and after redaction, and the opt-in Vision pair
(`FRISKET_VISION_OCR=1`). These checks need the signed app.

1. Capture a synthetic pattern that contains the word CANARY. Press **t**
   (or **Copy Text**). Confirm the notice is only **Copied N characters**
   and Notification Center does not show the recognized string.
2. Open the editor, solid-redact that word, Done. Press **t** again.
   Confirm the clipboard no longer contains CANARY.
3. Start Copy Text, then immediately Done with a redaction so the revision
   changes. Confirm no late clipboard write of the original text.
4. With VoiceOver on, the card exposes **Copy recognized text**.
