# 80: Slim checks and dead code

**What to build:** The repository checks keep only the six named invariants, run from `ci.sh`:

1. `AuthorizedFinalization` is built only by the coordinator;
2. the app writes nothing outside finalization;
3. storage never receives original pixels;
4. the core does no disk I/O;
5. no event taps or global monitors;
6. no network APIs.

The redundant regex rules, the Snapzy provenance and identity checks are deleted (ticket 87 already removed the stitcher, its fixtures and the Vision probe). So is the dead code: test-only public API, empty functions and files, the unread diagnostics (replaced by `os.Logger` with privacy annotations), and the Snapzy build scripts.

**Blocked by:** 67, 77 (70 withdrawn by decision 60)

**Phase:** 5 (O12, O17)

**Status:** ready-for-agent

- [x] Each of the six invariants has a passing and a failing fixture.
- [x] The `ci.sh` run time is recorded before and after.
- [x] Diagnostics use `os.Logger`, and Frisket writes no log files of its own (decision 25 still holds).

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62). Choices recorded as this ticket's decision in `decisions.md`.

- **Checks:** `Checks/check_repository.py` now holds the six invariants (`finalization`, `app-writes`, `storage-pixels`, `core-io`, `input-monitoring`, `network`), the core import allowlist (inside `core-io`, as CLAUDE.md requires) and ticket 77's `app-sources`. `ci.sh` runs them once, plus `--self-test`, which fails unless each check has a passing and a failing fixture (15 fixtures). `check_drift.py`, `retired-terms.tsv` and `ci.sh --defects` are unchanged. Deleted: `dependencies`, `imports`, `identity`, `provenance`, `diagnostics`, `silgen`, `modals`, the storage eager-write, capture-case and clipboard-declaration regexes, the hot-key count, 35 old fixtures, `docs/ported-files.json`, and the Swift suite's second run of every check (and `d22ProductCodeBindsNoCFunctionThroughSilgenName`, which ran the deleted `silgen` check; D22 is fixed). The suite file is now `ToolingChecksTests.swift` (the Tools unit tests only).
- **Diagnostics:** `LocalDiagnosticLog` and `DiagnosticRecord` removed (retired terms). New adapter `SystemDiagnosticLog` (os.Logger, public-marked closed enum values only) is injected by `FrisketApp` into the coordinator and `HistoryStore`. Test: `SystemDiagnosticLogTests`. Diagnostic tests now use a test-target `RecordingDiagnostics`; the seven-day in-memory expiry test is deleted with the log it tested.
- **Dead code:** `FrisketCore.swift`, `discardSelectionPreviews` (and its fakes and preview-only assertions), `familyIdentifiers`, `ClipboardImage.currentHostOnly/.concealed`, `HistoryEntry.imageLocation/.thumbnailLocation` (moved to a test extension), `Codable` on diagnostic types, `build-snapzy.sh`, `measure.py`'s `snapzy` tool. Docs updated (`core-package.md`, `app-build.md`, the ticket 37 runbook, ADR 0001).
- **`ci.sh` wall time:** before, 152 s cold (caches rebuilt after they pointed at ticket 86's worktree) and 30 s warm (repository checks 4 s); after, 26 s warm (repository checks 2 s). `ci: green`, 415 tests.
- **Open:** `DragSessionEvents` in the coordinator has empty methods, but the drag adapter's sequencing calls them through `DragCopyEvents`; removing that seam is a drag refactor, not dead code. No live-matrix rows.
