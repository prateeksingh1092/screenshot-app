# What the builder implements, in order

Label: wayfinder:task
Status: resolved
Type: task
Parent: [Frisket visual implementation route](../map.md)

## Question

Glass placement and the Annotation cue are decided. Record the ordered build a later session can implement, with the file, the measurements, and which source supplies each number. Do not implement. Do not edit `docs/design/2026-09-24-registration.md` or `docs/design/2026-09-24-design-plan.md`.

Locked before this ticket:

- [Where custom Liquid Glass may sit](01-where-custom-liquid-glass-may-sit.md). One regular `NSGlassEffectView` on the thumbnail controls only. The editor uses the stock toolbar. The scrolling panel uses stock buttons. The selection hint and badge are a solid fill. Do not hand-paint `windowBackgroundColor` as a Reduce Transparency replacement.
- [Which annotation cue the route uses](03-which-annotation-cue-the-route-uses.md). One signal-red ink, `RGBAPixel(255, 59, 48, 255)`, plus a 1-output-pixel white plate. The rasterization seam is narrowed, not dropped. No swatches.
- Solid redaction stays `RGBAPixel(0, 0, 0, 255)`. Shortcuts, retention, and the capture lifecycle stay.

The order has to name where the keyboard manual lives after it leaves the overlay, and which document supplies a number when both plans describe the same behavior. Registration's capsule radii, four-ink swatches, and scrolling glass card are not sources for those surfaces. A Dock icon, a color picker, and the other out-of-scope items on [Frisket visual implementation route](../map.md) stay out.

## Answer

Proceed. The UI and UX reviews (visual hierarchy, capture interaction, accessibility, materials) and the four architecture reviews agree. Daily-use order wins. Architecture corrections sit inside the steps.

1. Selection and window pick. One 0.40 veil, a clear hole, black-then-white strokes, corner ticks, an opaque badge. Manuals leave the glass for `accessibilityHelp`. The non-origin notice stays, as a solid chip. No `FrisketCore` change. Started in this session.
2. Thumbnail. The image is an opaque sibling. One regular `NSGlassEffectView` holds only the controls and the status. Copy stays the word. The other actions are symbols. Dismiss is no longer a button. Failure lines are announced. Do not paint `windowBackgroundColor` for Reduce Transparency. Started in this session.
3. Editor. Remove the `.menu` shelf. A stock toolbar must not double-count `EditorWindowLayout`'s in-content shelf. Letter keys leave `keyEquivalent` and are handled only when the field editor is inactive. The conceal hint stays in the content view. The drag well stays opaque. Guides separate solid redaction from the red ink. Baked pixels wait for step 5.
4. Scrolling panel. `makeKey()` and `makeFirstResponder` after selection hides. `becomesKeyOnlyIfNeeded` is false. Done and Cancel get key equivalents. Dropping the title requires an `NSPanel` subclass that overrides `canBecomeKey`. No event monitor. Stitcher notice strings stay verbatim. No glass card.
5. Annotation plate and system-font masks. The plate is a constant white write in `DocumentRenderer.draw`, after the second redaction fill, the whole ring before any ink, and it skips pixels inside a solid redaction. `outputCount` has no floor of 1. Update `textUsesTheClosedBitmapFont` and `annotationsAppearOnEveryOutputWithoutWeakeningRedactions`.
6. History and the sheets, then the template status symbol. Keep the onboarding phrases and the scrolling notice sentences the tests lock.

User testing of each small control follows the implementation, on the synthetic pattern only.
