# Frisket visual implementation route

Label: wayfinder:map

## Destination

One implementation route for the Frisket visual pass. The conflicts between the Registration spec and the independent design plan are decided from evidence, and a builder can start without choosing a design fork.

## Notes

The domain is the visual and interaction pass around an already-specified capture loop. Use the language in `CONTEXT.md`: Capture, Scrolling capture, Annotation, Solid redaction, Pending capture, Finalized capture, History, Export. The word "chrome" in the two design documents means the controls around a capture. It is not a new domain term.

Decision 54 in `.scratch/screenshot-mvp/decisions.md` already says design forks are decided from evidence, not left for the owner to pick. Do not grill the owner on these forks.

This map produces decisions, not the UI. Do not edit `docs/design/2026-09-24-registration.md` or `docs/design/2026-09-24-design-plan.md` from a ticket. The independent plan was written without reading Registration.

Source documents:

- `docs/design/2026-09-24-registration.md`, committed as `2bb6ff7`
- `docs/design/2026-09-24-design-plan.md`

Solid redaction stays `RGBAPixel(0, 0, 0, 255)`, square, and separate from Annotation. The floor stays macOS 26. Skills for open tickets: research against primary sources.

## Decisions so far

- [What the UX-8 rejection still allows](issues/02-what-the-ux-8-rejection-still-allows.md) — None of the four parts is forbidden. The bundle missed the agree-bar; “lack of support” is that summary, not a merits finding. A plate was not balloted. More than one ink is allowed and not required.
- [Where custom Liquid Glass may sit](issues/01-where-custom-liquid-glass-may-sit.md) — Glass on the thumbnail controls only. The editor uses the stock toolbar. The scrolling panel uses stock buttons. The selection hint and badge are a solid fill.
- [Which annotation cue the route uses](issues/03-which-annotation-cue-the-route-uses.md) — One signal-red ink plus a 1-output-pixel white plate. The rasterization seam is narrowed, not dropped. No swatches.
- [What the builder implements, in order](issues/04-what-the-builder-implements-in-order.md) — Daily-use order: selection, thumbnail, editor, scrolling, annotation plate, then sheets. Manuals move to VoiceOver help. The plate never recolors a redaction.

## Not yet specified


## Out of scope

Dock icon and Icon Composer artwork. The independent plan set this aside. It does not make the capture loop quieter.

Recording, pin, cloud, accounts, frames, gradients, device bezels, a freeform pen, stickers, a screen ruler, a color picker, History re-edit, and any export format other than PNG.

Changes to shortcuts, retention, the solid-redaction pixel contract, or the capture lifecycle.

Writing the UI. This map ends when the route is clear.
