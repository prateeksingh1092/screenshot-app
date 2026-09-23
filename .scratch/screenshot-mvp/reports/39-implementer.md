# Ticket 39 implementer

Model: Cursor coordinator chat (Claude Opus 5.5 High). Codex and Other Models
are past included-usage limits.

## Seams

- Offline Python: `Tools/FirstRun/record.py` writes a closed-field first-run
  record (date, OS, commit, lipo architectures, codesign identifier/team/cdhash,
  sanitized display layout, permission enum). It refuses PNG/JPEG/GIF bytes,
  the substring `png`, serial numbers, and free-text notes.
- `firstRunRecordSatisfiesOfflineChecks` runs those unittests from Swift Testing.
- The bundled pattern remains `Tools/FrisketTestPattern.swift`: 320×180 points
  at display centre; `--verify` checks dimensions and marker pixels.

## What landed

- Record writer, four offline tests, `scripts/first-run-record.sh`.
- Index runbook `docs/manual-checks/39-first-run.md` mapping the spec cases
  onto existing 08/18/23/24/32 checklists.
- Hardware, Screen Recording, VoiceOver, and second-display steps not run.
  x86_64 only; arm64 not executed.

Stopped before review. Ticket Status/checkboxes unchanged.
