# 27: Crop

**What to build:** Prateek crops a capture in the editor, and redactions stay complete after cropping and scaling.

**Blocked by:** 26

**Status:** ready-for-agent

- [ ] Redaction rectangles are snapped outward to whole output pixels after crop and scale.
- [ ] Pre-crop display frames are discarded right after cropping.
- [ ] Canary cases cover 1x and 2x sources, fractional rectangles, and crop across every available output.
- [ ] Seam 2 render-equivalence and frozen-snapshot cases.

## Comments
