# Ticket 11 — fresh review (Claude Opus 5.5 High via the Cursor CLI), 2026-09-23

Fixed point `6b651a0`, snapshot `f88348a`. Codex (GPT-6 Astra, high) implemented this ticket. The reviewer's root `swift test` run passed 89 tests in 13 suites, with 3 skipped.

## Answers to the brief

1. **Shared policy:** passes. Save goes through Copy's branch and commit cache, and retries reuse the recorded commit. `SaveOutcome` reports the commit and the delivery separately.
2. **History failure:** the behaviour is correct. User story 71, decision 40 and the retention section's "delivery continues" all require it, and it matches ticket 09's Copy, including the acknowledgement notice.
3. **Export:** passes. It writes the in-memory frozen bytes and creates files exclusively (`O_EXCL|O_NOFOLLOW`). Exports are never registered with History.
4. **Stored path:** a plain path is acceptable for an unsandboxed target.
   - If the folder is removed, it is recreated at the old path. A folder the user renames isn't followed.
   - An unmounted volume fails as unwritable, and Retry Save stays available.
   - Desktop, Documents and Downloads may need macOS permission after a relaunch; a denied write reports `.unavailable`.
5. **Settings:** see the should-fix under Spec.
6. **Tests:** pass.
7. **Hygiene:** passes. Diagnostics use closed enums, and there's no scope creep.

## Standards

- **should-fix**, `CaptureLifecycleCoordinator.swift` (the Copy/Save branch): duplicated delivery bookkeeping, selected by a pair of flags. Tickets 12 and 31 will add a third copy, so extract one delivery step.
- **nit**, same file: `copyCommits` and `failedDelivery` now hold Save's state as well as Copy's. The names are misleading.
- **nit**, `CaptureExport.swift`: `SaveOutcome` has the same shape as `CopyOutcome` (a data clump).
- **nit**, `ExportSettings.swift`: the whole Settings shell is named after one section.
- **nit**, `ExportSettingsView.body`: it runs a synchronous filesystem assessment on every render, on the main thread.

## Spec

- **should-fix**, `FrisketApp.swift`: the new main menu contains only Settings. It has no Close (⌘W), Quit (⌘Q) or Edit menu, so keyboard users can't close Settings or copy the path. This breaks user story 77.
- **should-fix**, `PNGFileExporter.assess` and `ExportFolderPolicy`: only this build's root is refused. A debug build can export into the installed build's `History.noindex`, which user story 73 forbids.
- **should-fix**, same location: a firmlink path under `/System/Volumes/Data/…` bypasses the comparison. Compare file identity on the existing ancestors.
- **nit**, `FrisketApp.save`: rejected outcomes return silently, whereas Copy marks itself failed.
- **nit**, `PNGFileExporter.export`:
  - a partial file is visible under the final name during the write;
  - files get `0600` permissions;
  - there's a check-then-use gap on intermediate symlinks.
- **nit**, `ThumbnailPanel.swift`: after a failed Save, the card shows the Save message and "Dismiss to keep in History." at the same time.
- **nit**: ⌘, works only while a Frisket window is key. Keep this in the manual check.
- **Conflict risk:**
  - high with tickets 12 and 13;
  - medium with ticket 26;
  - low with ticket 10.

Verdict: fix-then-merge
