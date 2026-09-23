# 28: Arrows, shapes, and text labels

**What to build:** Prateek adds arrows, shapes, and text labels in the editor, and they appear in every delivered output.

**Blocked by:** 26

**Status:** resolved (tested on `main` at `72ab1c3`; annotation VoiceOver/canvas manual pending)

- [x] Shapes are a separate tool from Solid redaction and can't be made into a see-through or rounded "redaction".
- [x] Annotations render above redactions without weakening them.
- [x] Seam 2 pixel tests for each annotation type.
- [x] Tool controls have VoiceOver labels and keyboard operation.

## Comments

### 2026-09-23 — coordinator

Claimed on `c665f89` after ticket 27 closed. Coordinator chat implements (Codex/Other Models still limited). Branch `ticket/28-arrows-shapes-text`.

### 2026-09-23 — implementer

Report: [28-implementer.md](../reports/28-implementer.md). Seam 2 covers outline, arrow, letter A, and annotations above redactions. Seam 1 canaries cover every output. Manual not run. Status/checkboxes unchanged pending review.

### 2026-09-23 — review

In-chat review vs `c665f89`: [28-code-review.md](../reviews/28-code-review.md). No blocking findings.

- **Integration:** `integrate/28` fast-forwarded `main` to `72ab1c3`. Annotations are a separate opaque layer above redactions, with a built-in 5×7 font. Seam 2 covers outline, arrow, letter A, and annotations above fill. Seam 1 canaries cover every output. Root `swift test`: 263 tests in 37 suites passed. Unsigned x86_64 `xcodebuild` succeeded. x86_64 only; arm64 not executed. Coordinator chat after Codex/Other Models limits. Manual annotation canvas/VoiceOver remain for Prateek.

