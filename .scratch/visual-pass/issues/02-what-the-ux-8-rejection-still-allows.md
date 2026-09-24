# What the UX-8 rejection still allows

Label: wayfinder:research
Status: resolved
Type: research
Parent: [Frisket visual implementation route](../map.md)

## Question

`.scratch/screenshot-mvp/decisions.md` records UX-8 as not adopted, for lack of support, and able to return later. The amendment in `.scratch/red-team/round1/ux.md` bundled Reduce Motion, Increase Contrast, Reduce Transparency, a colorblind default palette with named colors in a picker, selection state never by color alone, and an Accessibility Inspector audit.

The independent design plan reads that rejection as "no palette policy." It keeps red as the default Annotation ink, adds a non-color plate where the desktop is arbitrary, and still specifies display-setting fallbacks. Registration specifies four baked inks and halos, the same display-setting fallbacks, and no color picker.

What does the rejection forbid, and what does it leave open? Separate these four:

1. Honoring Reduce Motion, Increase Contrast, and Reduce Transparency.
2. A second non-color cue, such as weight or a plate.
3. More than one Annotation ink.
4. A color picker.

Cite the decision record, the UX-8 text, and any reconcile note that states why support was lacking. Do not adopt UX-8 by answering. Do not edit either design document. Solid redaction stays opaque black and is not an ink.

## Answer

None of the four parts is forbidden. UX-8 was one bundle. It missed the adoption bar (one author agree, seven abstains, no objection, tally `UX-8 [-]`), and `decisions.md` summarizes that as “not adopted … for lack of support; it can return later.” Those words are not in the ballots. There is no UX-8 reconcile note.

1. Reduce Motion, Increase Contrast, and Reduce Transparency are left open. Decision 24 does not mention them.
2. A plate or a heavier stroke, with no new palette, was not balloted. The rejection does not require it or forbid it.
3. More than one Annotation ink is left open. One red ink is also allowed. Neither is required.
4. A color picker is left open by UX-8. This map already places a color picker out of scope, and this answer does not bring it back.

The independent plan’s “no palette policy” reading matches non-adoption. It overreaches if it is taken to prohibit a palette. Registration’s four inks are not required by this record and are not forbidden by it.

Findings: branch `research/ux8-annotation-cue`, commit `8c4bc7a`, file `docs/research/2026-09-24-ux8-annotation-cue.md`.
