# 27: Crop

**What to build:** Prateek crops a capture in the editor, and redactions stay complete after cropping and scaling.

**Blocked by:** 26

**Status:** in-progress (branch `ticket/27-crop`)

- [ ] Redaction rectangles are snapped outward to whole output pixels after crop and scale.
- [ ] Pre-crop display frames are discarded right after cropping.
- [ ] Canary cases cover 1x and 2x sources, fractional rectangles, and crop across every available output.
- [ ] Seam 2 render-equivalence and frozen-snapshot cases.

## Comments

### 2026-09-23 — coordinator

Claimed on `226ff32` after ticket 17 closed. Coordinator chat implements (Codex/Other Models still limited).

### 2026-09-23 — implementer

Report: [27-implementer.md](../reports/27-implementer.md). Seam 2 covers crop+redaction snap, 1×/2×, equivalence and snapshot. Seam 1 canaries cover every output. Manual not run. Status/checkboxes unchanged pending review.

### 2026-09-23 — review

In-chat review vs `226ff32`: [27-code-review.md](../reviews/27-code-review.md). No blocking findings.
