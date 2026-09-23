# Ticket 40 verification draft

Model: Cursor coordinator chat (Claude Opus 5.5 High). Not a v1 declaration.
Codex assessment is still required and is unavailable until 2026-09-29 11:57.
x86_64 only; arm64 not executed.

## Automated evidence on `main` at `5c095bf`

- Root `swift test` on `integrate/39` (`9810f19`): **292 tests in 43 suites**.
- Unsigned x86_64 `xcodebuild` (`CODE_SIGNING_ALLOWED=NO`) succeeded there.
- Static checks (dependencies, imports, identity, provenance, diagnostics,
  capture-memory, input-monitoring, app-sources) passed through
  `RepositoryChecksTests`.
- Ticket 36 peak on 5120×57,600: **586,006,528** bytes, under 2 GB.
- Ticket 33 Vision pair on Version 26.7 (Build 25G229): CANARY (6) unredacted,
  0 after redaction.
- Ticket 39 live header against `~/Applications/Frisket.app`: macOS 26.7
  (25G229), x86_64, team `9M43Q952NK`, one built-in Retina 3584×2240 /
  1792×1120, 21 first-run cases still `pending`.

## Still open (not a pass)

- Hardware first-run index: [39-first-run.md](../../../docs/manual-checks/39-first-run.md).
  External 1× display, TCC state account, VoiceOver, two signed rebuilds.
- Every earlier manual checklist that decision 49 left for Prateek.
- Live performance vs ratified targets (tickets 37/38). Placeholders stand.
- Universal signed Release labelled "arm64 built and signed, never executed".
  Unsigned Release compiled on this host: `lipo` reports `x86_64 arm64`,
  identifier `io.github.prateeksingh1092.frisket`. `codesign` with the
  existing Apple Development identity timed out (keychain prompt). The
  bundle was not launched or copied to `~/Applications`. arm64 not executed.
- Codex assessment of this report.

Nothing in this draft is a distribution or Apple-silicon runtime claim.
