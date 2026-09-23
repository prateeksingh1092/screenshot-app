# 31: Copy, Save, and drag from the editor

**What to build:** Copy, Save, or dragging from the editor finalizes the flattened result and delivers exactly what Prateek sees.

**Blocked by:** 11, 12, 26

**Status:** resolved (tested on `main` at `6d892ee`; editor Copy/Save/drag VoiceOver manual pending)

- [x] Each action finalizes the rendered revision through the shared finalization policy, then delivers it.
- [x] Delivery failure leaves the commit intact and can be retried on the same revision.
- [x] Canary cases on the saved file and the dragged file.

## Comments

### 2026-09-23 — coordinator

Claimed on `5d0d6a5` after ticket 30 closed. Coordinator chat implements (Codex/Other Models still limited). Branch `ticket/31-editor-copy-save-drag`.

### 2026-09-23 — implementer

Report: [31-implementer.md](../reports/31-implementer.md). Copy, Save, and drag finalize through Done then deliver the rendered revision. Manual not run. Status/checkboxes unchanged pending review.

### 2026-09-23 — review

In-chat review vs `5d0d6a5`: [31-code-review.md](../reviews/31-code-review.md). No blocking findings.

- **Integration:** `integrate/31` fast-forwarded `main` to `6d892ee`. Editor Copy, Save, and drag finalize the canvas then deliver. Root `swift test`: 278 tests in 38 suites passed. Unsigned x86_64 `xcodebuild` succeeded. x86_64 only; arm64 not executed. Coordinator chat after Codex/Other Models limits. Manual editor Copy/Save/drag remain for Prateek.

