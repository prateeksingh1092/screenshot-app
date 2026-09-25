# Ticket 40 implementer

Model: Cursor coordinator chat (Claude Opus 5.5 High). Codex and Other Models
are past included-usage limits. Not a v1 declaration.

## Seams

- Offline: `Tools/Release/test_project.py` keeps Development on native
  `x86_64` / `.frisket.debug` and Release on `x86_64`+`arm64` /
  `io.github.prateeksingh1092.frisket`.
- Offline: `Tools/Release/label.py` writes
  `arm64 built and signed, never executed` only for that universal signed
  identity, and refuses install or launch.
- `releaseProjectSatisfiesOfflineChecks` runs those unittests from Swift Testing.

## What landed

- Release configurations on the project, Frisket, and FrisketCore targets.
- Archive scheme uses Release; Launch stays Development.
- `scripts/release-universal.sh` (never copies to `~/Applications`).
- Index: `docs/manual-checks/40-final-acceptance.md`.

Unsigned universal Release compiled (`lipo`: `x86_64 arm64`). Signing the
production bundle timed out on the keychain. Hardware, ratified targets, and
Codex assessment remain open. arm64 compiled, never executed.
