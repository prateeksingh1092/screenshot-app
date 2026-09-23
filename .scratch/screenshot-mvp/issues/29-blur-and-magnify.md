# 29: Blur and magnify over the redacted composite

**What to build:** Prateek can place blur or magnify effects, and an effect placed over a redaction can never reveal what's under it.

**Blocked by:** 26

**Status:** in-progress (branch `ticket/29-blur-and-magnify`)

- [ ] Solid redactions are applied to the base layer before any pixel-sampling effect; effects read only the redacted composite.
- [ ] Blur is an annotation effect, never offered as a redaction method.
- [ ] Canary cases with overlapping blur and magnifier across every available output.

## Comments

### 2026-09-23 — coordinator

Claimed on `ad7aa9c` after ticket 28 closed. Coordinator chat implements (Codex/Other Models still limited). Branch `ticket/29-blur-and-magnify`.

### 2026-09-23 — implementer

Report: [29-implementer.md](../reports/29-implementer.md). Seam 2 covers magnify, blur, and overlapping effects over fill. Seam 1 canaries cover every output. Manual not run. Status/checkboxes unchanged pending review.
