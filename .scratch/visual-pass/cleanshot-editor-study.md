# CleanShot X editor study (2026-09-24)

Prateek asked for this study: "I absolutely hate how the arrow and text is such a limited capability right now … study CleanShot's editor – it's so smooth."

**Method.**
- CleanShot X 5.0.1 (Setapp) opened a synthetic 800×600 scroll-page render in its Annotate window. It was driven through accessibility and the live-harness `drive` tool, with one-command owner overrides.
- No settings were changed, and the edits were discarded with Don't Save. CleanShot was quit afterwards, because it had not been running. The clipboard was saved and restored.
- Screenshots of CleanShot's own window only are in `cleanshot-editor/`, which git ignores.
- The official feature list (cleanshot.com/features) fills in what wasn't tried by hand.

## What makes it feel smooth

1. **Every mark stays an object you can change.** Choose the select tool, or click a mark: it gets a blue outline and handles.
   - An arrow has two end handles and a **middle handle that bends it into a smooth curve**. The head turns to follow the curve (`05`, `06`).
   - A text label has side handles for width and a corner handle for size (`08`).
   - Marks can be moved, resized and restyled after they are drawn. In Frisket, a mark is final once drawn: undo is the only way back.
2. **Text is typed in place on the image.** Click, then type. You see the real font at the real size while you type, with a caret and a box (`07`). `v2.1 $4.99 -10%` came out exactly (`08`). Frisket takes the text in a toolbar field, and its 5×7 bitmap font drops lowercase letters and `$ . - %` (D6).
3. **The toolbar follows the tool.** With the Arrow tool it shows colour, line width and arrow style. With the Text tool it shows colour, size (10–288 pt) and text style.
4. **The arrows look good:** a tapered shaft with a solid, well-shaped head, antialiased. Frisket's arrow is a thin stroke.
5. **Exits never hide.** "Save as…" stays at the top right, and Copy, Share, Pin, Upload and a "Drag Me" handle stay in a bottom bar. Closing with edits asks Save / Don't Save / Cancel (`10`). This is Frisket's D5, which ticket 53 fixes.

## Side by side

| Area | CleanShot X | Frisket today (build 8) |
|---|---|---|
| Arrow | 4 styles: Standard (tapered), Fancy, Curved, Double. Bend handle, end handles, width, colour | 1 straight style, fixed red, fixed width. Can't be changed after drawing |
| Text | Typed on the image. 7 styles: Standard, Rounded, Outlined, Mono, Box, Mono Box, Rounded Box. 13 sizes, from 10 to 288 pt. Real font | Toolbar field, then drag a box. 5×7 bitmap font, uppercase A–Z, 0–9 and space only (D6) |
| Shapes | Rectangle, filled rectangle, ellipse, line | Outline rectangle only |
| Other marks | Counter (step numbers), highlighter with text-size detection, pencil with smoothing, spotlight | none |
| After drawing | Select, move, resize, bend, restyle | Undo only |
| Colour | Colour picker with saved favourites | One fixed red |
| Concealment | Pixelate ("randomization"), blur, filled rectangle in any colour. **No verified opaque redaction** | **Solid redaction, exactly the chosen palette colour at alpha 255 (black by default) and verified** (decision 61, ticket 88). Blur and Magnify never conceal |
| Tool accessibility | Tools are unlabelled images for VoiceOver (e.g. `annotateArrowTool`) | Every tool is labelled (a Frisket strength) |
| Crop | Aspect ratios and snapping to edges | Free crop |

## Recommendation

Build on Phase 2. The native renderer (tickets 65–67: CoreGraphics strokes and CoreText labels) is the base. Without it, curved arrows and real text are impossible. Then add editing in this order:

1. **Editable marks** (foundation). A select mode with handles: move, resize and delete a mark, and change its colour or width after drawing. Undo covers each change (it builds on ticket 69's `NSUndoManager`). This single change removes most of the "limited" feeling.
2. **Arrows.** Tapered Standard arrows, plus Curved with a bend handle. Double-headed arrows and plain lines are cheap to add at the same time.
3. **Text.** Typing on the image with the real font, a size menu and a few styles (Standard, Outlined, Box). Label width comes from the side handle.
4. **More marks.** Ellipse, counter (step numbers) and highlighter. The pencil is later.
5. **Colour.** A small palette, such as red, yellow, blue, green, black and white, remembered between captures.

**Keep:** Solid redaction as the only concealment, labelled tools, and marks drawn above redactions.

## Decisions for Prateek (product-visible)

1. **Scope for v1.** I recommend items 1–3 in v1, and items 4–5 after v1.
2. **Filled rectangles.** Frisket forbids a fill today, so that a mark can never be mistaken for Solid redaction. If a filled rectangle is wanted, I recommend it only in colours other than black, with no fully opaque black. *Resolved by decision 61: no filled shapes at all; shapes are outlines, and Solid redaction (in a small neutral palette, black by default) is the only fill.*
3. **Pixelate.** CleanShot sells pixelate as redaction. I recommend Frisket doesn't add it, or adds it only as a softening effect like Blur, clearly labelled as not concealing.

After Prateek chooses, the chosen items become spec stories and tickets that follow ticket 66 and ticket 69.
