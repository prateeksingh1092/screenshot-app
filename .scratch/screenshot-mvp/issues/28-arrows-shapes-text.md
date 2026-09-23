# 28: Arrows, shapes, and text labels

**What to build:** Prateek adds arrows, shapes, and text labels in the editor, and they appear in every delivered output.

**Blocked by:** 26

**Status:** in-progress (branch `ticket/28-arrows-shapes-text`)

- [ ] Shapes are a separate tool from Solid redaction and can't be made into a see-through or rounded "redaction".
- [ ] Annotations render above redactions without weakening them.
- [ ] Seam 2 pixel tests for each annotation type.
- [ ] Tool controls have VoiceOver labels and keyboard operation.

## Comments

### 2026-09-23 — coordinator

Claimed on `c665f89` after ticket 27 closed. Coordinator chat implements (Codex/Other Models still limited). Branch `ticket/28-arrows-shapes-text`.

### 2026-09-23 — implementer

Report: [28-implementer.md](../reports/28-implementer.md). Seam 2 covers outline, arrow, letter A, and annotations above redactions. Seam 1 canaries cover every output. Manual not run. Status/checkboxes unchanged pending review.
