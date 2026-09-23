# 27 — Crop

Automated seam 2 covers outward snap after crop and scale, 1×/2×, fractional
rectangles, and a frozen snapshot. Seam 1 canaries cover every delivery output.
These checks need the signed app.

1. Capture, open the editor, press **C**, drag a crop. Confirm the canvas
   redraws at the cropped size and the previous full-frame image is gone.
2. Add a Solid redaction that crosses a crop edge. Done. Confirm Copy, Save,
   and History show opaque fill on every partly covered output pixel.
3. Undo the crop (⌘Z) and confirm the original frame returns.
4. VoiceOver: Crop tool and canvas labels mention crop.
