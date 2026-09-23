# Ticket 24 implementation

Implementer: Codex, GPT-6 Astra, medium (assigned brief). Stopped before review. Ticket status and acceptance checkboxes untouched. No refactoring stage, commits, signing, app launches, screen capture, clipboard use, or manual checklist execution. x86_64 verified; arm64 not executed.

## Delivered

- Carbon-only global shortcuts for every currently available global action: Area ⌃⌥⌘4, Full Screen ⌃⌥⌘3, Focus Latest Thumbnail ⌃⌥⌘T. Future Window/Scrolling actions are not present in this checkout.
- Settings key picker and modifier controls, Apply, per-action default restoration, persistent bindings, accessible labels and collision warnings. Picking combinations does not require pressing a system screenshot shortcut. Menu labels track active mappings.
- Startup, remapping, and dispatch validate against enabled symbolic shortcuts via Carbon `CopySymbolicHotKeys`. Failed queries or malformed data fail closed. Defaults use the same validation. Disabled system bindings can be remapped.
- Duplicate Frisket bindings and invalid modifier combinations are refused. Failed Carbon replacement retains the previous registration. Unique event IDs prevent queued events for replaced bindings from dispatching. One registration call site; no event taps or event monitors.
- Manual checklist: `docs/manual-checks/24-shortcuts.md` (not run).

## Verification

Five shortcut tests, including a four-case failure test, were developed red→green through the public shortcut command boundary and the OS-list decoding boundary. Red evidence covered missing behavior, duplicate/invalid mappings, failure preservation, startup/dispatch verification, and malformed system data. Initial focused runs used a dependency-free harness referencing the actual source/test files.

Full suite: **121 tests in 18 suites passed**, with three existing opt-in tests skipped (recorded scroll sequences, Vision probe, full-size memory run). See `24-tests.log`. All eight repository static checks passed, including input monitoring. All `Frisket/*.swift` and adapter sources passed Swift 6 typechecking against the compiled core for x86_64 macOS 26. No unsigned Xcode app build was performed.

The full test build initially exposed eight existing `SaveCommandsTests` calls missing the required permission argument. Those calls now pass the existing `GrantedTestPermission` fixture; no production capture behavior was changed. See `24-build.log` for the successful test build.

## Offline build recovery and deviations

The seeded module caches referenced the main checkout; they were moved aside locally. GRDB sources were absent from this worktree. A cached checkout from ticket-11 had recorded version 7.11.1 and revision `b83108d10f42680d78f23fe4d4d80fc88dab3212`, matching this project's lockfile. It was copied into `.build/offline-dependencies/GRDB.swift` preserving symlinks. The manifest temporarily used that local path for `swift build --build-tests` in `.build/offline-build`, then was restored. SwiftPM removed the root lockfile during local-path resolution; its original contents were restored afterward and the dependency static check passed again. The built test bundle ran through Xcode's `swiftpm-testing-helper` with `--testing-library swift-testing` and Xcode framework/library paths, avoiding package resolution during the suite.

Brief deviations: one read-only `git status --short` ran in the initial instruction read before the prohibition was noticed. Initial SwiftPM attempts also invoked internal git/fetch operations and failed; no successful fetch was reported. Subsequent verification used local sources only. No git mutations or review were performed.

Remaining human verification: actual Carbon dispatch/registration, Settings layout and accessibility, system shortcut coexistence on the installed app, and arm64. The manual checklist records these explicitly.
