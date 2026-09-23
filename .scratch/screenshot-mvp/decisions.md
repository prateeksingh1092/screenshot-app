# Screenshot app: product decisions

## Confirmed by Prateek

The user approved all three recommendations in the first Pocock grilling round.

1. **Audience:** Personal use first, with later distribution possible. Public distribution is not a first-version requirement.
2. **First-version workflow:** Area, window, and full-screen capture; annotations and solid redaction; clipboard, file saving, and dragging; OCR; scrolling capture. Recording is deferred.
3. **Storage and sharing:** Local storage first, with no account or recurring service costs. Cloud storage and hosted sharing are deferred.
4. **Capture interaction:** Floating thumbnail with copy, save, drag, and edit actions; editor opens on demand; configurable shortcuts.
5. **History:** On by default. Dismissing an unedited thumbnail saves the capture automatically. Opening the editor keeps it pending until Done, Copy, or Save finalizes the flattened result. Keep the unredacted original only during active editing. Retain history for a configurable 30 days or 1 GB, whichever limit is reached first; remove oldest history items automatically and leave explicitly exported files untouched. Prateek approved the Q7 and Q8 recommendations.
6. **Foundation evaluation:** Evaluate Snapzy's build and core workflows on the current Intel Mac before deciding whether to adapt it. Independently research its stack against alternative combinations; acceptance of an evaluation is not selection of Snapzy or its stack.
7. **Development tools and process:** Cursor desktop will be the project's IDE (explicit user clarification). Cursor CLI is authenticated and may support terminal tasks, but CLI participation alone does not satisfy this choice. Continue the local Matt Pocock research, grilling/domain-modeling, specification, ticketing, implementation, and review process.
8. **Models and orchestration:** Codex leads the project and may use Cursor Ultra's models and other capabilities when they are better suited or complementary. This latest user clarification supersedes the earlier Codex-only restriction. Codex owns integration and final assessment; delegated work has explicit scope and provenance.
9. **Billing:** Existing ChatGPT and Cursor Ultra included allowances only. No pay-per-use/API-key billing, paid overages, extra credits, add-ons, or new subscriptions. Codex uses ChatGPT sign-in; complementary Cursor work uses the existing Ultra account. Stop at included-usage limits rather than activating paid fallback.
10. **Cursor spending verification:** Prateek explicitly confirmed that On-demand spending is disabled. This is user-verified account state, not an independent dashboard inspection by Codex; the earlier pending-confirmation blocker is resolved.
11. **Cursor model:** Use native Cursor Claude Opus 5.5 at high effort for complementary work. Codex remains the lead and assesses its output.
12. **Immediate evaluation priority:** Ask Cursor Claude Opus 5.5 whether full Xcode is actually needed before attempting installation. Distinguish building an arbitrary native app with Command Line Tools from building unmodified Snapzy's Xcode project.

## Architecture grilling round (approved by Prateek, 2026-09-22)

Prateek approved all thirteen recommendations of the architecture round. Evidence: [history adaptation](../../docs/research/2026-09-22-snapzy-history-adaptation.md), [local-only surface](../../docs/research/2026-09-22-snapzy-local-only-surface.md). A red-team review follows; its consensus amendments are recorded below this section.

13. **Foundation strategy:** Build a new native app that ports selected Snapzy parts (scrolling stitcher, renderer, capture overlay, database layer) under Snapzy's BSD-3-Clause license, rather than forking Snapzy or writing everything from scratch. Reason: the capture-lifecycle invariant cuts across Snapzy's URL-based plumbing, so a fork would diverge enough to forfeit upstream merges.
    **Amended by Prateek, 2026-09-22 (after the red-team port question, unanimous across eight roles):** Build the app fresh and use Snapzy as a read-only engineering reference; do not port its renderer, capture overlay, capture engine, or database layer. The scrolling stitcher (`ScrollingCaptureStitcher.swift`) is the only port candidate, decided by a short trial: it compiles alone in a scratch package, passes its tests on this Intel Mac, stays under 2 GB on a synthetic 5120×57,600 capture after moving to strip storage, and costs less than a fresh implementation. The trial involves builds and needs Prateek's approval when scheduled. Any ported code keeps its BSD-3 header and provenance entry. See [ADR 0001](../../docs/adr/0001-build-fresh-snapzy-as-reference.md).
14. **Toolchain:** Install an Intel-compatible full Xcode (26.6, after confirming its installer); keep core logic in a Swift package that also builds without Xcode.
15. **Platform floor:** macOS 26 or later; universal binary (x86_64 + arm64) from day one. Lower the floor only when distribution becomes real.
16. **Original during editing:** The unredacted original exists in memory only. A crash during editing loses that pending capture.
17. **Leaving the editor:** Dragging from the editor finalizes the current rendered result. Closing with edits asks Finalize / Delete capture / Cancel. Never save the unredacted original after redaction has begun.
18. **1 GB accounting:** Counts all app-owned bytes (finalized images, thumbnails, database); exports excluded. Enforced after every commit and at launch; the just-committed item is never evicted. Settings shows usage.
19. **Automation surface:** No URL scheme or App Intents in v1. All actions go through one internal command layer so App Intents can be added later.
20. **History image format:** PNG only in v1, stored in an app-owned directory, with versioned database migrations from the first release and ownership/lifecycle state in the schema.
21. **Later distribution:** Deferred. v1 is locally signed with no updater; bundle identifier, entitlements, and an update seam are kept ready. Any future update feed belongs to this project, never upstream.
22. **Performance targets:** Measure baselines (macOS built-in screenshot tool, signed Snapzy release) first, then set targets. Starting placeholders: thumbnail visible within 500 ms; idle CPU under 1%; scrolling-capture peak memory under 2 GB.
23. **Test boundaries:** Automated fixture tests for the capture lifecycle, retention, stitcher, renderer pixels (including opaque-redaction checks), OCR-on-rendered-result, and forced-quit recovery. A scripted manual checklist covers permission-dependent capture, overlays, and multiple displays.
24. **Accessibility and language:** English only; full keyboard operation of capture and thumbnail; VoiceOver labels on all controls except canvas contents.
25. **Diagnostics:** Local-only logs, 7-day retention, events and error codes only: never pixels, OCR text, clipboard contents, or capture file names.

## Naming (chosen by Prateek, 2026-09-22)

26. **App name:** Frisket. A frisket is the mask laid over part of an image so paint or ink cannot reach it, which names the Solid redaction feature. Bundle identifier `io.github.prateeksingh1092.frisket`, permanent from the first signed build; development builds use `io.github.prateeksingh1092.frisket.debug`. The repository folder stays `screenshot-app`. Conflict checks were web searches only; run a trademark search before any public release. Candidates and conflicts are in `../red-team/status.md`.

## Red-team outcome (2026-09-22)

Prateek asked for a red-team review and for the mutually agreed amendments to be incorporated. Eight roles reviewed the plan (Principal Architect in Codex GPT-6 Astra high; seven Cursor Claude Opus 5.5 High roles). Rule: an amendment is adopted when at least two roles other than its author agree and none object.

- **Adopted by panel consensus (57):** ARCH-1, 3, 4, 5, 6, 7; UX-1, 2, 3, 4, 5, 6; QA-1 to QA-8; DATA-1 to DATA-8; REL-1, 2, 3, 4, 6, 7, 8; PERF-1 to PERF-7; SEC-1, 2, 3, 4, 5, 7, 8; PLAT-1 to PLAT-8. Text: `../red-team/round1/<role>.md`, with the conditions accepted in `../red-team/round2/reconcile-<role>.md` taking precedence. REL items about porting apply only if the stitcher trial ports it.
- **Panel conflicts (unanimous):** commit protocol is file-first (write, `F_FULLFSYNC`, atomic rename, then one row), with only `finalized` and `deleting` states; development builds are native-architecture only, universal builds only for release, and nothing is distributed before it runs on Apple silicon.
- **Superseded:** ARCH-2, REL-5. **Not adopted:** UX-8 (display-setting accessibility), for lack of support; it can return later.
- Tally and ballots: `../red-team/round2/`.

## Prateek's answers to the red-team questions (2026-09-22)

27. **Oversized capture:** a single capture larger than the 1 GB history limit is refused from History, with a notice; copy, save, and drag still work. This overrides the panel's unanimous preference to keep it with a visible overage, and keeps decision 5's ceiling intact.
28. **No History re-editing in v1:** History items are finished images to copy, drag, export, or delete (resolves ARCH-4).
29. **Shortcuts:** coexist with macOS. Defaults avoid enabled system screenshot shortcuts (⇧⌘3/4/5, and ⇧⌘6 on Touch Bar Macs) and can be remapped.
30. **Logout or restart during the editor's Finalize / Delete capture / Cancel prompt:** discard the pending capture.
31. **Unedited thumbnail:** stays in memory until acted on; a crash loses it.
32. **Scrolling capture:** manual scrolling only in v1; no Accessibility permission.
33. **Area selection:** confined to the display where it started.
34. **Test displays:** the built-in Retina display plus an external non-Retina (1x) display.
35. **Backups:** History is excluded from Time Machine (resolves SEC-6).
36. **Clipboard:** copies stay on this Mac (no Universal Clipboard) and are marked so clipboard managers skip them.
37. **Capture exclusion list:** per-app, empty by default.
38. **Default export folder:** `~/Pictures/Frisket`.
39. **Export:** per-item only; no "export all history" in v1.
40. **History database failure:** capturing, copying, saving, and dragging still work; History is off with a visible notice and a recovery option.
41. **Stitcher trial:** convert its tests to Swift Testing first.
42. **Signing identity:** Xcode Personal Team via Prateek's Apple ID, created when the first build needs it.
43. **Repository:** private for now; choose a license only if published.
44. **Exit outcomes (confirmed 2026-09-22 during ticket review):** closing the editor without edits finalizes to History; thumbnail timeout, swipe, close, overflow, and Esc finalize to History; Delete capture discards; quit finalizes unedited thumbnails; unplugging a display moves its thumbnail to a remaining display; screen lock leaves it pending.
45. **Ticket breakdown:** the 40 tickets in `issues/` were approved as drafted (granularity and blocking edges), after Codex's assessment.
46. **Autonomous implementation (2026-09-22 21:51):** Prateek asked for autonomous execution. Codex (GPT-6 Astra, high) writes all code; the Cursor agent coordinates, runs independent tickets in parallel when dependencies allow, and checks Pocock adherence (implement → tdd → code-review → commit). In-plan builds, tests, and commits after review are approved under this grant. Still gated on Prateek: Apple ID, keychain, or signing-identity changes; capturing real screen content; clipboard use; installs; any paid usage.
47. **Xcode version (2026-09-22):** pin Xcode 26.5 (17F42, macOS SDK 26.5, Swift 6.3.2), installed from the Mac App Store, instead of the planned 26.6. Revisit 26.6 later. Swift tests run with Xcode's toolchain via `DEVELOPER_DIR`, because the Command Line Tools lack Swift Testing (found in ticket 02).
48. **Stitcher: port (2026-09-22, ticket 05):** Ticket 34 ports the adapted Snapzy stitcher from `Trials/StitcherTrial/` instead of writing a fresh one. The evidence: 29 trial tests pass; a 5120×57,600 capture stitches in full at a 1.28 GB peak, under the 2 GB limit; Vision alignment works outside Codex's sandbox. Codex's low-confidence estimate is 2–4 hours to port versus 8–16 hours fresh. The BSD-3 notices and provenance stay. Reassess with a bounded fresh prototype if real scroll sequences reveal broad correctness problems. Report: `reports/05-port-or-fresh.md`.

## Evaluation update: Xcode question resolved narrowly

The requested Cursor Opus 5.5 high review completed and Codex assessed it. The installed CLT compiled/linked a native-framework probe and ran it without screen capture; Preview and XCTest probes failed for missing tooling. Full Xcode is not a universal native-app requirement, while Snapzy's existing source build/tests still depend on Xcode tooling. This is factual evaluation evidence, not approval to change the foundation or port its build system. See [Codex's assessment](../../docs/research/2026-09-22-xcode-necessity-assessment.md).

These are accepted product choices, not approval of a particular source-code foundation, architecture, or complete implementation specification.

## Evidence

- [Research and Grok cross-review](../../docs/research/2026-09-22-cross-review.md)
- [Feature landscape](../../docs/research/2026-09-22-screenshot-landscape.md)
- [Repository comparison](../../docs/research/github-repositories.md)

Research has not yet established buildability or capture reliability on this Mac through hands-on testing.

## Next decisions

- Foundation and stack selection after independent research and hands-on feasibility evidence.
- First-version behavior, acceptance criteria, and test boundaries.

## Subsequent work

Resolve behavior and acceptance criteria, confirm the shared understanding and testing boundaries, publish the specification, then create implementation tickets. Do not treat pending recommendations as requirements.
