# 33: Copy recognized text

**What to build:** Prateek copies the text in a capture, recognized from the rendered result, so redacted text is never extracted.

**Blocked by:** 26

**Status:** resolved (tested on `main` at `03b0e8f`; Copy Text VoiceOver/notice manual pending)

- [x] Vision runs only on the rendered revision; results for a stale revision are dropped.
- [x] The notification says only "Copied N characters".
- [x] Recognized text is never stored or logged.
- [x] Seam 1 tests use a text-recognition stand-in.
- [x] A tagged, local-only real Vision pair: canary text recognized when unredacted, absent once redacted; the OS build is recorded.

## Comments

### 2026-09-23 — coordinator

Claimed on `9617e93` after ticket 31 closed. Coordinator chat implements (Codex/Other Models still limited). Branch `ticket/33-copy-recognized-text`.

### 2026-09-23 — implementer

Report: [33-implementer.md](../reports/33-implementer.md). Copy Text recognizes
the current revision only, drops stale results, and notices the character
count. Manual not run. Status/checkboxes unchanged pending review.

### 2026-09-23 — review

In-chat review vs `9617e93`: [33-code-review.md](../reviews/33-code-review.md). No blocking findings.

- **Integration:** `integrate/33` fast-forwarded `main` to `03b0e8f`. Copy Text
  recognizes the current rendered revision, drops stale results, and notices
  only the character count. Root `swift test`: 285 tests in 41 suites passed
  (one isolated re-run of `interruptedFinalizationBytesAreStillAccountedAtLaunch`
  after a `.rootLocked` flake during a parallel xcodebuild). Unsigned x86_64
  `xcodebuild` succeeded. Tagged Vision pair on Version 26.7 (Build 25G229):
  CANARY (6) unredacted, 0 after redaction. x86_64 only; arm64 not executed.
  Coordinator chat after Codex/Other Models limits. Manual Copy Text remains
  for Prateek.

