# Frisket v1: draft ticket breakdown, revision 2 (not published)

Status: approved by Prateek and published as `issues/01-40` (2026-09-22). The ticket files are authoritative; this draft is kept for provenance.
Provenance: revision 1 drafted by Cursor Claude Opus 5.5; Codex (GPT-6 Astra, high) assessed it as "rework" (`../red-team/tickets-assess-codex.md`); revision 2 applies all 14 of Codex's changes, cross-cutting ones as acceptance criteria.
Source: `spec.md`. Numbers are in dependency order (blockers first).

Cross-cutting criteria on every UI ticket: VoiceOver labels and keyboard operation for its controls. On every ticket that adds an interruption point: extend the named commit-point list and its crash cases.

1. **Repository hygiene before the first commit** | Blocked by: none | Third-party notices (GRDB, copied skills), extended ignore rules, staged-diff secret review, first commit on approval. No licence (decision 43).
2. **Core package skeleton and toolchain probe** | none | Package builds without Xcode; `swift test` with Swift Testing runs under the Command Line Tools; static checks: GRDB-only allowlist (no networking), dependency direction, identity scrub, licence headers.
3. **Install Xcode 26.6** (human) | none | Downloaded from Apple, signature-checked, SDK pinned.
4. **Stitcher trial, part 1: extract and test** | 2 | Snapzy stitcher compiles alone in a scratch package; its tests converted to Swift Testing pass on this Mac.
5. **Stitcher trial, part 2: strip storage and memory run** | 4 | Strip storage, 5120×57,600 synthetic run under 2 GB, port-or-fresh recommendation; Prateek decides.
6. **Capture to Copy through the command layer** | 2 | Command layer and lifecycle coordinator with fixture pixel source and recording clipboard: typed capture identifiers, separate commit and delivery outcomes, retries on the same revision, stale and duplicate commands rejected, global pending-byte budget, closed-set diagnostics logging with planted-secret test. Verified by `swift test`.
7. **Create the Personal Team signing identity** (human) | 3 | Created when ticket 8 first needs a signed build (decision 42).
8. **Real area capture to a thumbnail to Copy** | 6, 7 | Menu-bar app with `.debug` identity and storage root, Carbon shortcut, single-display area selection, ScreenCaptureKit self-excluding filter, thumbnail with Copy, concealed current-host clipboard. Hardened runtime, minimal entitlements (no network), stable signing so the permission survives rebuilds, no event taps or idle monitors.
9. **Dismiss finalizes into History** | 8 | File-first commit with finalization record, GRDB store, baseline migration with fixtures (never erase, auto-vacuum, secure delete, refuse unknown), `.noindex` root excluded from backup, root-relative paths, "Kept in History", disposable thumbnail cache.
10. **Launch recovery sweep and crash-recovery tests** | 9 | Locked idempotent sweep, record-validated adoption, tier 1 and tier 2 cases per commit point, coverage check, home-folder rename and restore reconciliation.
11. **Save to the export folder, with the Settings window shell** | 9 | Save through the shared finalization policy to `~/Pictures/Frisket` (copy, never move); export folder setting with iCloud warning and refusal inside the app-owned root.
12. **Drag handoff with file promises** | 9 | Copy-only promise of the rendered revision through the shared finalization policy; staging cleanup and its crash cases.
13. **Thumbnail stack and Delete capture** | 9 | Stacked thumbnails on the capture display over full-screen Spaces; Delete capture; timeout, swipe, close, overflow, and Esc outcomes.
14. **Thumbnail outcomes on quit, display, and lock events; auto-dismiss setting** | 11, 13 | Quit finalizes unedited, unplug moves, lock leaves pending, crash loses unedited; auto-dismiss delay or never in Settings.
15. **History window** | 9, 11, 12 | Newest first; copy, drag, export, delete (hidden `deleting`, direct unlink) with crash cases.
16. **Retention and quota** | 9, 11 | 30 days / 1 GB in Settings, oldest-first eviction with tie-breaking, oversized refusal with notice, clock-anomaly deferral, eviction notice and Settings line, crash cases.
17. **History database failure mode** | 9, 11, 12 | History off with notice and recovery option; capture, copy, save, and drag proven still working.
18. **Selection overlay across displays** | 8 | Crosshair on every display, origin-display confinement, negative coordinates, clean cancel on unplug, full-screen apps and Space switches.
19. **Selection precision** | 8 | Device-pixel magnifier, Shift/Option/Space/arrows, Esc without activation.
20. **Full-screen capture** | 8 | Capture a whole display.
21. **Window capture** | 8 | Click a window on the current Space; highlight ignores Frisket's panels.
22. **Capture exclusion list** | 8, 11 | Settings list, empty by default, applied to every capture filter.
23. **Screen Recording permission states and recovery** | 8 | Five-state model, check before any overlay, recovery panel, menu-bar indicator, no overlay over a pending system alert.
24. **Shortcut defaults and remapping** | 8, 11 | Defaults avoid enabled system screenshot shortcuts incl. Touch Bar; remapping validated, fail-closed.
25. **Onboarding and About window** | 23 | Permission, what History keeps, Save keeps a permanent copy, privacy limits; third-party notices.
26. **Editor tracer: Solid redaction to a flattened result** | 9 | Open from thumbnail, Solid redaction, Done finalizes the rendered revision, thumbnail refresh, clipboard replacement if unchanged; no autosave, restoration, or caches; renderer tests and canary tests on clipboard, History, and thumbnail outputs.
27. **Crop** | 26 | Outward pixel snapping, pre-crop frame discard; canary cases for 1x, 2x, fractional rectangles, and crop.
28. **Arrows, shapes, and text labels** | 26 | Rendered and delivered, with pixel tests.
29. **Blur and magnify over the redacted composite** | 26 | Sampling effects read only the redacted composite; overlap canary cases.
30. **Editor close, quit, and logout choices** | 26 | Finalize / Delete capture / Cancel; close without edits finalizes; per-editor Quit choice; sudden termination off; interrupted logout discards.
31. **Copy, Save, and drag from the editor** | 11, 12, 26 | Each finalizes and delivers the flattened revision; canary cases on saved and dragged files.
32. **Keyboard and VoiceOver thumbnails** | 11, 13, 26 | Focus shortcut, arrows, single keys for copy, save, edit, Delete capture, dismiss; VoiceOver actions and announcements; auto-dismiss pauses under focus.
33. **Copy recognized text** | 26 | OCR on the rendered revision, stale results dropped, "Copied N characters", real Vision positive and negative pair.
34. **Stitcher adoption: port or fresh** | 5 | Implements Prateek's trial decision; either path passes the same tests.
35. **Scrolling capture** | 9, 34 | Manual scroll with live preview, strips, pending-byte refusal, cap and memory stop message; to thumbnail, copy, and History.
36. **Editing a long scrolling capture** | 26, 35 | Tiled or downsampled proxy; strip-by-strip rendering and PNG encoding.
37. **Performance baselines: macOS tool and Snapzy** | 3 | Scripted measurements of the reference tools.
38. **Frisket performance measurement and target ratification** | 8, 37 | Idle CPU, wakeups, footprint, latency; Prateek ratifies targets.
39. **Manual hardware checklist, first recorded run** | 18, 19, 20, 21, 23, 24, 32 | Test-pattern window, output-check script, recorded run of every required case so far.
40. **Final acceptance** | 10, 14, 15, 16, 17, 22, 25, 27, 28, 29, 30, 31, 33, 36, 38, 39 | Complete checklist, performance rerun after scrolling, universal release build labelled "arm64 built, never executed", all static checks.
