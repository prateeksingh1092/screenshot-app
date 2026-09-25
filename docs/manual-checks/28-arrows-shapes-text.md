# 28 — Arrows, shapes, and text

Automated seam 2 covers rectangle outline, arrow head, bitmap letter A, and
annotations drawn above redactions without clearing neighbour fill. Seam 1
canaries cover History, thumbnail, Copy, Save, and drag. These checks need
the signed app.

1. Capture, open the editor. Press **S**, drag a rectangle. Confirm it is an
   outline in the fixed red stroke, not a filled black redaction.
2. Press **A**, drag an arrow. Press **T**, click the canvas and type a label
   on the image, then press Return (ticket 86: it ends the label, not the
   editor). Confirm the letters appear above any Solid redaction and stay opaque.
3. Done. Confirm Copy, Save, and History show the same annotations.
4. VoiceOver: Arrow, Shape, Text, the label text being typed, and the Label
   Size and Label Style menus have spoken names.
   **S**, **A**, and **T** select the tools without a modifier.
