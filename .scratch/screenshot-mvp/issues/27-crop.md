# 27: Crop

**What to build:** Prateek crops a capture in the editor, and redactions stay complete after cropping and scaling.

**Blocked by:** 26

**Status:** resolved (tested on `main` at `5a287b9`; crop VoiceOver/canvas manual pending)

- [x] Redaction rectangles are snapped outward to whole output pixels after crop and scale.
- [x] Pre-crop display frames are discarded right after cropping.
- [x] Canary cases cover 1x and 2x sources, fractional rectangles, and crop across every available output.
- [x] Seam 2 render-equivalence and frozen-snapshot cases.

## Comments

### 2026-09-23 — coordinator

Claimed on `226ff32` after ticket 17 closed. Coordinator chat implements (Codex/Other Models still limited).

### 2026-09-23 — implementer

Report: [27-implementer.md](../reports/27-implementer.md). Seam 2 covers crop+redaction snap, 1×/2×, equivalence and snapshot. Seam 1 canaries cover every output. Manual not run. Status/checkboxes unchanged pending review.

### 2026-09-23 — review

In-chat review vs `226ff32`: [27-code-review.md](../reviews/27-code-review.md). No blocking findings.

- **Integration:** `integrate/27` fast-forwarded `main` to `5a287b9`. Outward snap after crop and scale, 1×/2× canaries on every output, and seam 2 equivalence/snapshot are automated. Root `swift test`: 257 tests in 37 suites passed. Unsigned x86_64 `xcodebuild` succeeded. x86_64 only; arm64 not executed. Coordinator chat after Codex/Other Models limits. Manual crop canvas/VoiceOver remain for Prateek.
