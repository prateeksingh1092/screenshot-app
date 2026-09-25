# Ticket 33 implementer

Model: Cursor coordinator chat (Claude Opus 5.5 High). Codex and Other Models
are past included-usage limits.

## Seams

- Seam 1: `copyRecognizedText` on the current revision. Stand-ins return
  canary text while the source pixels are visible and empty after Solid
  redaction. Stale results after Done are dropped.
- Tagged local Vision: `FRISKET_VISION_OCR=1` pairs unredacted CANARY with
  a fully redacted negative and records the OS build.

## What landed

- `TextRecognizer` / `TextClipboard` / count-only `RecognizedTextOutcome`.
- Coordinator loads pending or History pixels, awaits OCR without holding
  `inProgress`, then writes the clipboard only if the revision is still
  current. Diagnostics never include the string.
- App: `VisionTextRecognizer`, `PasteboardAdapter.writeText`, thumbnail
  Copy Text / `t` / VoiceOver, notice **Copied N characters**.

Focused suite: `RecognizedTextCommandsTests`, stand-in canaries,
pasteboard `writeText`, and thumbnail key `t` — passed. Tagged Vision pair
with `FRISKET_VISION_OCR=1`: CANARY recognized (6 characters) when
unredacted, 0 after redaction. OS build **Version 26.7 (Build 25G229)**.
x86_64 only; arm64 not executed.

Stopped before review. Ticket Status/checkboxes unchanged.
