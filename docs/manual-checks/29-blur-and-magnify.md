# 29 — Blur and magnify

Automated seam 2 covers 2× magnify from the snapped origin, a 3×3 box blur,
and overlapping blur+magnify over a redaction. Seam 1 canaries cover every
delivery output. These checks need the signed app.

1. Capture, open the editor. Press **R**, redact a coloured region. Press
   **B**, drag blur over that redaction. Confirm the fill stays opaque black
   and the original colour does not return.
2. Press **M**, drag magnify over the same redaction. Confirm the magnified
   pixels stay black.
3. Done. Confirm Copy, Save, and History still hide the redacted colour.
4. VoiceOver: Blur and Magnify have spoken names. **B** and **M** select
   the tools without a modifier.
