# 33: Copy recognized text

**What to build:** Prateek copies the text in a capture, recognized from the rendered result, so redacted text is never extracted.

**Blocked by:** 26

**Status:** in-progress (branch `ticket/33-copy-recognized-text`)

- [ ] Vision runs only on the rendered revision; results for a stale revision are dropped.
- [ ] The notification says only "Copied N characters".
- [ ] Recognized text is never stored or logged.
- [ ] Seam 1 tests use a text-recognition stand-in.
- [ ] A tagged, local-only real Vision pair: canary text recognized when unredacted, absent once redacted; the OS build is recorded.

## Comments

### 2026-09-23 — coordinator

Claimed on `9617e93` after ticket 31 closed. Coordinator chat implements (Codex/Other Models still limited). Branch `ticket/33-copy-recognized-text`.

### 2026-09-23 — implementer

Report: [33-implementer.md](../reports/33-implementer.md). Copy Text recognizes
the current revision only, drops stale results, and notices the character
count. Manual not run. Status/checkboxes unchanged pending review.

