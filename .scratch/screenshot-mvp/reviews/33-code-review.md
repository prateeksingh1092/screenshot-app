# Ticket 33 code review

Fixed point: `9617e93` (merge-base with main). Review snapshot: `7bce37c`.
Model: Cursor coordinator chat (Claude Opus 5.5 High). In-chat review; Other Models and Codex are past included-usage limits.

## Standards

- OCR is a command-layer seam (`TextRecognizer` / `TextClipboard`) with a
  Vision adapter. The core never stores the string.
- `RecognizedTextOutcome` is count-only. Diagnostics add
  `.copyRecognizedText` / `.recognitionUnavailable` and no payload field.
- The recognizer await yields the coordinator actor so Done can make the
  revision stale. Judgement: `inProgress` is intentionally not held.

## Spec

- Ticket 33: Vision runs on the current rendered revision; stale results
  are dropped and do not write the clipboard.
- Notice title is only `Copied N characters`.
- Seam 1 stand-ins return canary text before redaction and empty after.
- Tagged Vision pair (`FRISKET_VISION_OCR=1`) recognized CANARY (6) on
  Version 26.7 (Build 25G229) and 0 after redaction.
- Manual thumbnail / VoiceOver checks remain.

## Summary

Standards: 0 hard findings. Spec: 0 blocking gaps. Worst per axis: the
success notice is an `NSAlert` title rather than Notification Center, which
still keeps recognized text out of NC.
