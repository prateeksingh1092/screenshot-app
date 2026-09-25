# 29 — Blur and magnify

Automated seam 2 covers 2× magnify from the snapped origin (CoreGraphics), a
3×3 box blur (vImage, edge-extended at its box), overlapping blur+magnify over
a redaction in each palette colour, and a stable output hash. Seam 1 canaries cover every
delivery output. These checks need the signed app.

1. Capture, open the editor. Press **R**, redact a coloured region. Press
   **B**, drag blur over that redaction. Confirm the fill stays exactly the
   chosen redaction colour and the original colour does not return.
2. Press **M**, drag magnify over the same redaction. Confirm the magnified
   redacted pixels stay the redaction colour.
3. Done. Confirm Copy, Save, and History still hide the redacted colour.
4. VoiceOver: Blur and Magnify have spoken names. **B** and **M** select
   the tools without a modifier.
