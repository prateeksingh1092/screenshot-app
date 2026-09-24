# Where custom Liquid Glass may sit

Label: wayfinder:research
Status: resolved
Type: research
Parent: [Frisket visual implementation route](../map.md)

## Question

For each borderless surface below, which treatment do the macOS 26 SDK and Apple's Materials guidance support: `NSGlassEffectView` whose `contentView` is only the controls, stock toolbar or stock buttons with no custom glass view, or a solid fill?

- Pending-capture thumbnail
- Editor shelf
- Scrolling-capture panel
- Selection hint and measurement badge

Registration (`docs/design/2026-09-24-registration.md`) specifies regular glass on the thumbnail, on both editor capsules, and on the scrolling panel, and a solid badge for the selection hint. The independent design plan (`docs/design/2026-09-24-design-plan.md`) specifies custom glass only around the thumbnail's controls, stock controls for the editor and the scrolling panel, and no glass on selection.

Answer with one placement per surface. Trace each placement to a primary source: the Materials HIG, Adopting Liquid Glass, WWDC25 session 310, `NSGlassEffectView.h` in the local macOS 26 SDK, or the current call site. Do not choose a look beyond what those sources support. Do not edit either design document. Captured pixels, the selection hole, and Solid redaction are not materials.

## Answer

Liquid Glass is the control layer. It is not a content material, and it samples past its own bounds.

- Pending-capture thumbnail: one `NSGlassEffectView`, regular, whose `contentView` is only the controls and the status line. The image is an opaque sibling and does not overlap the glass. The panel has no title bar, so there is no system toolbar plate to use instead.
- Editor shelf: the stock toolbar of the titled window. No custom glass view. The drag well shows captured pixels, so it stays out of the glass. The current `.menu` backdrop comes out.
- Scrolling-capture panel: stock buttons, no custom glass view. The preview stays an opaque image. The panel is titled today. If the title bar is removed later, Done and Cancel use the system glass bezel (`NSBezelStyleGlass`, macOS 26.0). They still do not sit in an `NSGlassEffectView` card.
- Selection hint and measurement badge: a solid fill. No glass sample on the drag path.

Registration’s editor capsules and scrolling glass card go past what the sources support, and its thumbnail image must not sit on top of the glass. Its selection prose matches this answer. The independent plan matches these four placements. Both plans overreach where they replace Reduce Transparency or Increase Contrast with a hand-painted `windowBackgroundColor`. The sources say the system changes the material and that custom glass has to be tested. They do not say to skip `NSGlassEffectView`.

Findings: branch `research/liquid-glass-placement`, commit `254d749`, file `docs/research/2026-09-24-liquid-glass-placement.md`. Checked here: the scrolling panel’s style mask is `[.titled, .nonactivatingPanel]`, and `NSBezelStyleGlass` is in `NSButtonCell.h` as of macOS 26.0.
