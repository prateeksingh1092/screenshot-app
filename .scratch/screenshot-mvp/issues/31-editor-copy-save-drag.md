# 31: Copy, Save, and drag from the editor

**What to build:** Copy, Save, or dragging from the editor finalizes the flattened result and delivers exactly what Prateek sees.

**Blocked by:** 11, 12, 26

**Status:** in-progress (branch `ticket/31-editor-copy-save-drag`)

- [ ] Each action finalizes the rendered revision through the shared finalization policy, then delivers it.
- [ ] Delivery failure leaves the commit intact and can be retried on the same revision.
- [ ] Canary cases on the saved file and the dragged file.

## Comments

### 2026-09-23 — coordinator

Claimed on `5d0d6a5` after ticket 30 closed. Coordinator chat implements (Codex/Other Models still limited). Branch `ticket/31-editor-copy-save-drag`.

### 2026-09-23 — implementer

Report: [31-implementer.md](../reports/31-implementer.md). Copy, Save, and drag finalize through Done then deliver the rendered revision. Manual not run. Status/checkboxes unchanged pending review.

### 2026-09-23 — review

In-chat review vs `5d0d6a5`: [31-code-review.md](../reviews/31-code-review.md). No blocking findings.

