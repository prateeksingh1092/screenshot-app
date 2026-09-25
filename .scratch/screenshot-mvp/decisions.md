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
49. **Manual checks while Prateek is away (2026-09-22 23:55):** ticket 08 merges once its automated checks, review, and integration pass. Its manual criteria stay open and are listed as pending in the ticket: first launch, the Screen Recording grant, real capture and Copy, and the grant surviving two rebuilds. Downstream tickets continue where they can be verified without real screen capture. Each carries its own manual items as pending, to be run with Prateek on his return. Nothing captures the real screen before his grant.
50. **Standing approvals for unattended work (2026-09-23 00:17):** this amends decision 46. Prateek approves:
    - installing and replacing signed Frisket debug builds (`io.github.prateeksingh1092.frisket.debug`) at the single path `~/Applications/Frisket.app`;
    - launching those builds;
    - once he has granted Screen Recording, capturing only Frisket's synthetic test-pattern window;
    - writing those synthetic images to the clipboard.

    Never capture any other window, the full screen, or real content, and never keep captures in the repo. Apple ID, keychain and signing-identity changes, other installs, and any paid usage remain gated on Prateek.
51. **Blanket approval (2026-09-23 02:18):** Prateek set Cursor to allow all permissions ("Everything is allowed"). This amends decisions 46 and 50. Agents may now, without asking:
    - run any local command, including `bash`, `ditto` and `codesign`;
    - make signed Frisket rebuilds and installs, using the existing identity;
    - build Snapzy from the read-only clone into a scratch location;
    - launch Snapzy and the macOS screenshot tool for ticket 37's baselines, capturing only the synthetic test pattern;
    - run the automatable parts of the manual checks.

    Still unchanged:
    - the billing policy: included allowances only, never paid usage;
    - the AGENTS.md kernel rules: no secrets in markdown, and never touching passwords or the DEAD memory paths;
    - no Apple ID or signing-identity changes;
    - no captures of real content, and no captures kept in the repo;
    - checks that need Prateek's eyes or keyboard stay pending for him.
52. **Throughput (2026-09-23 02:40):** Prateek approved four speed-ups to cut the remaining time.
    - Prioritise the critical path: tickets 26, 11 and 13, then 32 → 39 → 40.
    - Allow up to three concurrent tickets per model pool.
    - Seed each new worktree's `.build` cache from `main`.
    - Batch integration: 2–3 reviewed-and-fixed tickets merge into one integration branch, with one full suite run. On red, fall back to one-at-a-time merging to find the culprit.

    This amends step 7 of `docs/agents/implementation-workflow.md`. Every other step of the Pocock loop is unchanged.
53. **Effort mix (2026-09-23 02:42):** Prateek chose a hybrid effort level for Codex (GPT-6 Astra) and Grok 4.7. Claude Opus 5.5 stays at High.
    - **High:** all reviews and fix passes, plus the correctness-heavy tickets 10, 16, 17, 23, 26, 29, 33 and 35.
    - **Medium:** implementation of the interface and mechanical tickets 12, 13, 14, 15, 21, 22, 24, 25, 27, 28, 30, 31 and 38. For Codex that is `model_reasoning_effort="medium"`; for Grok, `grok-4.7-medium` (not -fast).
    - **Unlisted tickets:** implementation stays at High.
    - Runs already in flight are not restarted.
54. **No blocking product picks (2026-09-23 03:44):** Prateek will not choose among design forks. Alternate approaches are vetted by parallel agents against primary sources, then the coordinator applies the best-evidenced option and records it here. Architecture-wide changes still go through spec and tickets. Billing, secrets, real-content capture, and Apple ID / signing-identity changes stay forbidden.

    Immediate forks, now confirmed by the parallel vetting reports:
    - **Snapzy Release baseline (report `54-snapzy-baseline.md`):** v1 compares against the macOS screenshot tool only. This amends decision 22's two-comparator requirement for v1. Debug and patched Release Snapzy are not that comparator. Snapzy stays a read-only reference. The 500 ms placeholder stays until macOS numbers exist. A later signed Snapzy Release can be added if a future toolchain builds it.
    - **Thumbnail defaults (report `54-thumbnail-defaults.md`):** stack max 4 and auto-dismiss 10s are working defaults for ticket 13. Spec already makes auto-dismiss configurable, including never. Settings (ticket 14) can change them later. They are not ratified user-visible policy.

55. **Command–Shift number shortcuts (2026-09-23):** Prateek will replace CleanShot and wants captures on Command–Shift and a number, not Control–Option–Command. This supersedes decision 29 for the defaults. The defaults are ⌘⇧1 History, ⌘⇧2 focus the latest thumbnail, ⌘⇧3 full screen, ⌘⇧4 area, ⌘⇧5 window, and ⌘⇧6 scrolling page. Carbon registration stays. If macOS still has the screenshot symbolic hotkeys for ⇧⌘3/4/5/6 or their Control variants, Frisket turns those identifiers off (28, 29, 30, 31, 181, 182, 184), remembers which ones it changed, and can restore only those. An unchanged saved Control–Option–Command default migrates. A shortcut the user chose themselves stays. Remapping still fails closed on a system collision Frisket did not just claim, a duplicate, or an unverifiable system list. CleanShot may be quit so it releases these keys.
56. **Beta use on Intel and Apple silicon (2026-09-23):** Prateek wants other people to run Frisket and try it, not only an automated suite. Development builds follow the machine's architecture (`NATIVE_ARCH_64_BIT`): x86_64 on this Intel Mac, arm64 on Apple silicon. Release stays a universal binary. The floor remains macOS 26, which is the deployment target already in the project; lowering it is a separate compatibility pass. The project licence for Frisket itself is MIT so it can be circulated as open source. Third-party notices stay in `THIRD-PARTY-NOTICES.md`. This amends decision 43's "private, no project licence" for the moment of publication. A public remote is created only after a local use pass, and the repository must not gain signing secrets or captured personal pixels.
57. **Remediation decisions (2026-09-24):** Prateek delegated all technical choices ("I don't have enough technical knowledge; that's why I'm asking you"), in line with decision 54. The coordinator accepts the proposals in `Plans/dreamy-giggling-barto.md` §2. Evidence is in the plan's §1 and in `Plans/2026-09-24-session-handoff.md`.
    - **DA-1:** FrisketCore rendering may import CoreGraphics, CoreText, ImageIO and Accelerate. The core still does no disk I/O.
    - **DA-2** (amends the mechanism of 55; the ⌘⇧ defaults stay):
      - Frisket stops writing `com.apple.symbolichotkeys`.
      - It detects collisions read-only and deep-links to System Settings › Keyboard › Keyboard Shortcuts › Screenshots.
      - Restoring what Frisket turned off is opt-in.
    - **DA-3** (amends 17): a drag finalizes when a destination accepts the promise; a cancelled drag leaves the capture pending, with nothing on disk.
    - **DA-4** (with DA-11, amends the commit protocol behind 5, 18 and 20):
      - Keep 30 days / 1 GB.
      - Atomic PNG writes, GRDB at default durability, and a launch sweep that adopts orphan PNGs.
      - Sidecars, the ledger, the `F_FULLFSYNC` chain and the flock are removed.
      - History Delete asks for confirmation.
    - **DA-5:** notices are non-modal; modals only for destructive or irreversible choices.
    - **DA-6:** scrolling and edited output are capped at 32,768 px tall. Encoded size is used only for History admission (27).
    - **DA-7** (amends 7, 8, 45–53):
      - Merges are gated by `scripts/ci.sh`, a pre-push hook and the automated live harness.
      - Process artefacts go to `archive/`.
      - The lead agent is whichever one Prateek runs.
      - Hosted CI waits until the repository is public (billing, 9).
    - **DA-9:** the scrolling panel never takes key; ⌘⇧6 pressed again means Done.
    - **DA-10** (consistent with 28): History items can be restored to a Thumbnail that is already committed, with Edit disabled.
    - **DA-11:** see DA-4.
58. **Remediation tickets and Phase 0 choices (2026-09-24):** the coordinator made these choices under decisions 54 and 57, working from the plan's §1 evidence and the session handoff.
    - **Tickets:**
      - Tickets 42–83 in `issues/` implement the plan's Phases 0–6 and stories 82–101. The coordinator answered to-tickets' review step itself (decision 57).
      - Each Phase 1 fix is blocked by the red-test ticket for its seam. App-layer fixes with no seam are blocked by the live harness (48).
    - **Changes to the plan's phases:**
      - D1 keeps a Phase 1 interim (52). The save path renders the whole image with the same function the editor preview uses, for outputs up to 32,768 px tall. This overrides the handoff note "no D1 interim second render path". The interim adds no render algorithm: it reuses the preview's, drops the strip path for most outputs, and fixes a Critical defect before Phase 2. Ticket 65 deletes it.
      - D6 gets no interim. The interim would only have shown dropped characters, not kept them; CoreText labels (66) fix it.
      - D5 goes straight to the action bar (53), as D9 goes straight to fixed-size Thumbnails.
      - D13 goes straight to the full DA-2 (63), because decision 57 recorded it; there is no launch-only interim.
      - D26, the Loupe, is Phase 1 ticket 51.
    - **Known defects:**
      - A red test is wrapped in `knownDefect("Dn")`, a Swift Testing `withKnownIssue` that matches only failed expectations, so a thrown fixture error still fails the test.
      - The suite stays green while the defect exists and turns red when it is fixed, so the fix must remove the wrapper.
      - `FRISKET_SHOW_DEFECTS=1` runs the bodies unwrapped to show the reds.
      - Test names start with the defect ID.
    - **Build graph (42):**
      - The app links the package's `FrisketCore` product through a local package reference. The Xcode static-library target and the project's own GRDB pin are removed.
      - The workspace `Package.resolved` is a symlink to the root one.
      - `SDKROOT = macosx`.
      - Signing settings live in an untracked `Config/Signing.xcconfig`, with a tracked example. Without it, the build signs ad hoc, and the Screen Recording grant resets on every rebuild (decision 49).
    - **CI (43):**
      - `scripts/ci.sh` runs the static checks, the package tests and the unsigned app build.
      - A tracked `.githooks/pre-push` runs `ci.sh`.
      - The input-monitoring check moves from a per-build script phase into `ci.sh`.
      - A no-network check is added.
      - `@_silgen_name` is banned, except for the listed D22 uses.
    - **Live matrix:** the unattended run drives the real screen and clipboard, so it runs only when Prateek says he is away. Until then, the Phase 0 gate reports the harness as built and dry-run only.
    - **D27, a CI reliability fix (a product change during Phase 0):** `HistoryRootLock.acquire` retries a busy lock for up to 250 ms before reporting `.rootLocked`. Without it, `ci.sh` failed at random: 2 of 8 runs when History tests ran beside tests that start child processes. A live second owner still gets `.rootLocked`. Ticket 78 deletes the lock and the retry.
    - **Phase 1 choices:**
      - Ticket 59: Copy Text takes its own in-progress guard. Every command on that capture waits for it, except Done. Done may overtake Copy Text, because the stale-revision check already drops the old result; rejecting Done would make the user finish the edit twice.
      - Ticket 55: Copy Text with no text, or only whitespace, returns `.noTextFound` and writes nothing.
      - Ticket 53 (D5): Done, Copy, Save and the drag handle sit in a bar at the bottom of the editor's content area; the toolbar keeps the tools, the label field, Undo and Close. No editor button has a key equivalent. ⌘C (Edit › Copy), ⌘S (a new File › Save) and ⌘Z reach the editor window through the responder chain; Esc arrives as `cancelOperation:`; Return means Done only when the label field isn't editing. Return in the label field ends typing, so a second Return is Done; ⌘C there copies selected label text. Thumbnail and menu text says "add to History" instead of "keep in History".
      - Ticket 54 (DA-3): a drag commits only after the handoff reports an accepted drop. A cancelled or failed drag reports `DragOutcome.commit == nil` unless an earlier delivery already committed. An editor drag sends a new `.render` command instead of `.done`: the edit becomes the next pending revision, so a cancelled editor drag leaves History unchanged too.
      - Ticket 51 (D26): the Loupe samples live, not from a frozen preview. The deleted selection magnifier captured every display in full before the overlay appeared and repainted the whole overlay on each pointer move. The Loupe instead captures one 15 × 15 device-pixel square through the Selection's route (the same ScreenCaptureKit snapshot type, filter policy and exclusions), with at most one capture in flight; faster pointer moves collapse into the latest. Its snapshot is loaded after the overlay is on screen and must list Frisket's own process, so the filter leaves the overlay out; otherwise the Loupe stays hidden. It is layer-drawn, so moving it repaints nothing beneath.
    - **Effort level (Prateek, 2026-09-24):**
      - Tickets run at high effort.
      - Tickets 64, 65, 66, 67, 68 and 70 (the scrolling matcher and the native renderer) need xhigh. Before starting one, the coordinator stops and asks Prateek to switch; he changes the setting himself.
      - Correction: commits `656d253` to `d96e7b8` say "medium effort", but they ran at xhigh.

59. **Install approval and the editor's direction (Prateek, 2026-09-25):**
    - **Install:** Prateek approved installing a new signed Development build of `main` at the one install path in `docs/app-build.md`, replacing the running build 8, so the live harness can check the Phase 1 fixes. This approval covers the Phase 1 checks and Gate A; later installs ask again.
    - **Editor scope:** Prateek agreed with the recommendation in `.scratch/visual-pass/cleanshot-editor-study.md`.
      - **In v1:**
        - editable marks: select, move, resize, delete and restyle after drawing;
        - arrows: tapered Standard and Curved with a bend handle, plus Double and a plain Line;
        - text typed on the image in a real font, with a size menu and the Standard, Outlined and Box styles.

        Tickets 84–86 follow the native renderer (66) and `NSUndoManager` (69).
      - **After v1:** ellipse, counter, highlighter and a small colour palette.
    - **Filled rectangles:** allowed only in colours other than black, never as fully opaque black, so no mark can be mistaken for Solid redaction.
    - **Pixelate:** not added as concealment. If it is ever added, it is a softening effect like Blur, labelled as not hiding content.

60. **Scrolling capture and the Loupe removed; one-row Thumbnail; ticket 40 closed (Prateek, 2026-09-25):**
    - **Scrolling capture is removed as a feature.** This supersedes decisions 32 and 48 and the scrolling parts of decisions 2, 13 and 55. ⌘⇧6 is freed.
      - Retired stories: 4, 16, 17, 18, 81, 92 and 93, plus the ⌘⇧6 part of story 19.
      - Retired defects: D3, D11 and D20, plus DA-9.
      - Withdrawn tickets: 64, 70, 71 and 72.
      - The removal plan is in `Plans/2026-09-25-remove-scrolling-capture.md`.
    - **No Loupe while selecting.** Prateek had removed it on purpose; ticket 51 brought it back by mistake. This supersedes story 6, story 100 and D26, and ticket 51 is reverted.
    - **Thumbnail controls sit on one row.** Copy, Save, Edit, Copy Text and Delete share a single row.
    - **Ticket 40 (v1 final acceptance) is closed.** Ticket 83 (remediation acceptance) replaces it.

61. **Solid redaction colour is the user's choice (Prateek, 2026-09-25; first stated in spec story 42, 2026-09-22):**
    - **The choice:** the user picks the Solid redaction fill colour. It is not only black.
    - **The invariant:** every redacted pixel is exactly the chosen colour at full opacity (alpha 255), in every output: clipboard, file, drag, History, Thumbnail and OCR input. The default colour is black.
    - **What had drifted:** this choice was never recorded here. `CLAUDE.md`, the remediation plan, the CleanShot study and decision 59 all narrowed it to "exact black". This entry corrects them.
    - **Decision 59's filled-rectangle rule:** it assumed black redaction, so it has to be restated.
    - **Resolved by Prateek the same day:**
      - **No filled shapes.** Shapes are outlines only, so Solid redaction is the only solid fill in the editor. This replaces decision 59's filled-rectangle rule.
      - **A small palette:** black (the default), white, grey and a few neutral colours. There is no free colour picker.
    - **Ticket:** 88.

62. **Effort (Prateek, 2026-09-25):** medium effort for every remaining ticket. This supersedes decision 58's high default and its xhigh list (tickets 65–68). He chose this after being told the risk: the renderer and lifecycle tickets guard the Solid redaction and Pending capture invariants. The mitigation is that those tickets keep their test-first seams and the canary leak tests.

63. **Saved shortcuts outlive removed actions (coordinator, 2026-09-25, ticket 87):** `ShortcutAction.savedBindings(from:)` skips actions it no longer knows, such as `captureScrolling`. Without this, the saved `globalShortcuts.v1` preference would stop decoding and silently reset every shortcut the user had customised. Two tests cover it.
    - **Drift check:** `Checks/check_drift.py` runs in `ci.sh` and fails when a term retired by a decision (listed in `Checks/retired-terms.tsv`) appears in a live file.

64. **Capture renderer choices (implementer, 2026-09-25, ticket 65; under decisions 54 and 57):**
    - **Redaction colour as data:** each `SolidRedaction` carries its `colour` (default black). An initializer refuses any colour whose alpha isn't 255. Ticket 88 only adds the choice in the editor.
    - **Synchronous `flatten`:** the coordinator calls it with no suspension between its guards and the replacement of the original, so no in-progress guard moves. An async `flatten` must insert `inProgress` before the await.
    - **One whole-output bitmap:** captures are at most one display (decision 60), so there is no tile or strip path. The 32,768 px cap (DA-6) is read from the PNG header before decoding.
    - **PNG metadata:** the output keeps only the chunks that define pixels and colour (IHDR, IDAT, IEND and the sRGB tag). ImageIO adds an eXIf chunk even when given no properties, so the renderer drops every other chunk after encoding: no text, time, EXIF or resolution chunk.

65. **One Region request; window listings joined in the core (coordinator's delegate, 2026-09-25, ticket 75; decisions 57 and 60):**
    - **Region request:** the core's `RegionRequest.area`/`.fullScreen` turn a Selection or a whole display into the display ID, the display-local top-left source rectangle snapped to pixels, and the output size. The adapters no longer compute it.
    - **Displays and flips:** `CaptureDisplays` is the one place that finds a display by pointer (D14 rule), by ID or by largest overlap with a window, and the one place that flips between AppKit and top-left global coordinates.
    - **Display ID:** `CaptureImage` carries `displayID`, and the coordinator assigns the Thumbnail's display from it. The `captureDisplayID` side channels on both platforms are removed.
    - **Window listings:** `WindowSelection(rows:excluding:…)` joins the window-server list with ScreenCaptureKit's shareable windows and filters them, including the Capture exclusion list, so window mode's exclusion is package-tested.
    - **Not done here:** the area platform's step-by-step protocol (prefetch, prepare, select, hide, capture, finish) stays; collapsing it to `select`/`capture` would move the ordering tests behind AppKit. Ticket 77 (adapters as a product) may revisit it.

66. **Live-check cap (Prateek, 2026-09-25):** a harness run lasts 9 minutes at most per display, down from 15. That is how long the full built-in run took. `beta-matrix.sh` enforces it. A user test still lasts 15 minutes at most. Prateek also restated decision 54: every technical choice is the agent's, and nothing waits for him unless it is product-visible.

67. **One Pending capture record and one Thumbnail status (implementer, 2026-09-25, ticket 73; decisions 54 and 57):**
    - **Record:** the coordinator keeps one `PendingCapture` record per capture whose pixels are in memory, plus a settled map of how each released capture ended (finalized, delivered, discarded, recovery required) and its last revision. Two transient locks remain: a command in progress and a running Copy Text. There is no editing or delivering state.
    - **Status:** `thumbnails()` returns `Thumbnails`: each card's `status` (`pending` or `finalized`), whether it is `editable`, and `nextDueAt`, the earliest timeout still to come (nil while the stack is focused, the screen is locked, or a card awaits a retry). `CaptureSurfaces` applies the status and wakes once at `nextDueAt`; it no longer keeps arrival order, screens, per-card timers or its own commit flags.
    - **Accessibility (part of D16):** a finalized Thumbnail is named "Capture kept in History", and its custom actions drop Edit and Delete.
    - **Drag:** `.drag` runs through the shared `deliver()`. Copy and Save commit before the adapter write; a drag commits only after the destination accepts the drop (DA-3). A drag has no retry gate: dragging again is the retry.

68. **Native annotations (implementer, 2026-09-25, ticket 66; under decisions 54 and 57):**
    - **Where:** `AnnotationPainter` (in `CaptureRenderer.swift`) draws rectangles, arrows and labels with CoreGraphics and CoreText. The editor preview (`DocumentRenderer.render`) and `CaptureRenderer.flatten` both call it on the whole image, so the delivered image stays byte-equal to the preview.
    - **Order:** a white plate (the stroke widened by 1 px each side) for every annotation, then the Solid redactions again, then the ink. No plate pixel lands on a redacted pixel, and ink still draws above redactions.
    - **Labels:** pinned font `HelveticaNeue-Bold` (shipped with every macOS), 18 pt per document point, antialiased, font smoothing off. Any non-blank text is accepted; the 5×7 bitmap font (`AnnotationFont`) and the unused label seam `DocumentRenderer.outputCount` are deleted.
    - **Strokes:** 2 px (2 × scale) with square caps and mitred joins. A rectangle's stroke lies inside its snapped box, so it covers whole pixels and its golden is exact. Arrows keep the open two-wing head.
    - **Tolerance:** CoreGraphics antialiasing is not bit-identical between a short strip context and the whole image (a long near-vertical stroke moved up to 23 per channel on edge pixels). The strip walk (`forEachStrip`, no longer a production path since decision 64) is therefore compared to the whole render within 32 per channel for annotations; the delivered-vs-preview test and every Solid redaction golden stay exact. Drawing happens on row-reversed memory, so device y equals the output row and the first strip matches exactly.
    - **Open for ticket 67:** Blur and Magnify still differ in strips, so the effects half of the D1 test keeps `knownDefect("D1")`.

69. **Window capture offers unbundled apps' windows (implementer, 2026-09-25, ticket 89; decisions 54 and 57):** `WindowSelection` no longer rejects a window because its owner's bundle ID is empty. This amends plan item O2 and the D2 rule from ticket 49. Apps without a bundle ID (unbundled executables, some Java or Python apps) own real windows; live, the pattern window was `owner=pattern bundle=""` and window capture offered nothing. The cursor is excluded by what it is: its level, 2147483630 (`kCGCursorWindowLevel`), is above the Dock-level ceiling, and it is smaller than 32 pt. The Capture exclusion list still matches bundle IDs, so it cannot exclude an unbundled window.

70. **Render timing budget (implementer, 2026-09-25, ticket 90; decisions 54 and 57):** `RenderTimingTests` fails if `DocumentRenderer.render` or `CaptureRenderer.flatten` takes more than 250 ms (fastest of three, debug build) on the live repro: 800 × 1,000 px of opaque noise (a 2.8 MB PNG) at scale 2, one arrow and one label. Measured on this Intel Mac, debug: render 2–8 ms, flatten 120–130 ms, the whole Done command with a History commit 220–250 ms (also with 240 items in History), and the editor-open chain (`ThumbnailImage`, `bitmap(from:)`, render, `PNGBitmapCodec.image`) under 35 ms. The ticket's suspects (`AnnotationPainter`, a render per refresh, the PNG chunk filter, `forEachStrip`) are therefore not the live slowness, and no renderer code changed.

71. **History reads rows directly; the command layer is gone (implementer, 2026-09-25, ticket 74; decisions 54 and 57):**
    - **Coordinator is the action interface:** `CaptureCommandLayer` only forwarded to the coordinator, so it is deleted (retired term). `CaptureLifecycleCoordinator` is now the public actor the app and tests construct; `execute` records the closed diagnostics the layer used to record. Commands the coordinator runs for itself (Quit, a Thumbnail exit) are not recorded twice.
    - **History pass-throughs deleted:** `historyEntries`, `historyItems`, `historyThumbnail`, `historyImage`, `historyStatus`, `maintainHistory`, `recoverHistory` and `historyAvailability`. The History window and Settings call `HistoryStore` directly; the coordinator keeps only what it needs to commit and delete.
    - **Read model:** `HistoryStore.rows()` returns every row, newest first, in one query with no file names or paths. `thumbnailPNG(_:)`, `finalizedImage(_:)` and `delete(_:)` look one row up by ID (the capture identifier is unique and indexed) instead of reading every row.
    - **Window read model:** `HistoryList` (core, over the `HistoryRowSource` port that `HistoryStore` implements) holds the rows. A reload is one `rows()` query and no picture lookups, and it reports whether the rows changed, so an unchanged History does not redraw. A row asks for its picture by ID when it comes into view (the SwiftUI list is lazy); pictures are cached by capture and revision, at most 300. Before, each reload read every row's thumbnail one at a time, each through a full read, and republished the list after every row: live, with ~240 items and the window open, Done took 48 s (coordinator, 2026-09-25). Package tests count the reads for 240 rows and hold a real 240-row reload under 100 ms (measured 2–3 ms on the Intel Mac).
    - **Reload triggers stay:** a Thumbnail leaving by Copy, Save, Close or timeout commits a new row, so a visible History window must show it; each trigger now costs one query.
    - **`maintain` and `status` are `async` on `HistoryStore`:** as synchronous actor methods, a direct `await store.status(…)` resolved to the `CaptureHistory` extension's `.unavailable` default. The pass-throughs hid this because they called through the protocol.
    - **Accessibility (part of D16):** a History row is one accessibility element with one label; the picture well is not a second element.

72. **Native Blur and Magnify; Gate B at one display; encoder deleted (implementer, 2026-09-25, ticket 67; decisions 54, 57 and 60):**
    - **Blur:** `vImageBoxConvolve_ARGB8888`, 3 × 3, `kvImageEdgeExtend`, six passes, on a copy of the effect's snapped box of the redacted composite, written back. It rounds to nearest (the hand loop floored), so a 3 × 3 golden moved by 1 per channel.
    - **Magnify:** CoreGraphics draws the box's top-left quarter at 2× over the whole box (copy blend, no interpolation, no antialiasing), in a context the size of the box. Same pixels as before.
    - **What they read:** only their own box, after the redactions are stamped; the redactions are stamped again after them. A redaction under an effect stays exactly its colour at alpha 255. A pixel-hash golden locks the output on x86_64 (`effectOutputHashIsStable`); arm64 is unverified (no Apple-silicon Mac here).
    - **D1, effects half:** fixed. `forEachStrip` (a test oracle and the fallback, not a production path) widens each window to the whole rows of every effect box it meets, transitively, instead of a 1-row halo. Strips now equal the whole render exactly without annotations, and within decision 68's tolerance with them.
    - **Gate B:** passed on the whole-image path, so no per-strip fallback. Release build, this Intel Mac, `CaptureRenderer.flatten` with every edit kind (crop, redaction, rectangle, arrow, label, Blur over the whole image, Magnify): one display, 6,016 × 3,384, peak physical footprint 171.5 MB (166.9 MB before the save), save 1.4 s. For reference only, the DA-6 cap, 5,120 × 32,768, peaked at 2.35 GB including a 1.35 GB fixture, 11.9 s; no capture can reach it (decision 60), so it has no budget.
    - **Deleted:** `StripPNGEncoder` and its tests, the `@_silgen_name` zlib and libcompression bindings, and the `z` and `compression` link flags. The `silgen` check has no allowance list and no `--strict` flag; D22's test is unwrapped. No 5 × 7 font code remained (ticket 66 deleted `AnnotationFont`).

73. **Notices never block; Quit never refuses (implementer, 2026-09-25, ticket 76; DA-5, decisions 54 and 57):**
    - **One notice type:** FrisketCore's `Notice` (title, message, VoiceOver announcement) and `Notice.after(command, outcome)` decide what follows each command outcome. A success shows nothing; a failure the Thumbnail already shows with a Retry control (Copy, Save, drag, Close) stays only on its status line, so the old "Save failed" alert is gone.
    - **One notice service:** the app's `NoticeCenter` shows every `Notice` on a notice line: a non-activating glass panel near the menu bar on the pointer's display, with a Dismiss button, gone after 8 s, announced to VoiceOver at high priority. `AppController.notice` (a modal `NSAlert` for every notice, success included) is deleted.
    - **Modals:** only the `Confirmation` cases: History Delete, closing an edited capture (Quit reaches it through each open editor), and an export folder that syncs to iCloud (copies leave the Mac and can't be called back). The repository check `modals` (in `ci.sh`) fails when `NSAlert` appears outside `HistoryWindow.swift`, `EditorWindow.swift` and `ExportSettings.swift`.
    - **Quit (story 99):** `QuitPlan.steps(for:)` is the one place termination is decided. Only an open editor holds Quit. Live, a harness stopped mid-selection left the capture-in-progress flag set with no overlay visible, and Quit refused behind a modal "Finish the current action". Now Quit closes any selection overlay, waits at most 2 s for the capture command, at most 10 s for a running Copy, Save or drag, finalizes every pending capture into History, and quits. A capture still in memory when Quit goes on is dropped; nothing of it is on disk. If History refuses a capture, Quit stops and says so on the notice line.
    - **Open:** a stuck capture flag still blocks the next capture until the command returns; this ticket only stops it from holding Quit.

74. **Simpler History storage (implementer, 2026-09-25, ticket 78; DA-4 and DA-11, decisions 54 and 57):**
    - **Commit:** the PNG goes to `images/<UUID>.partial`, is renamed to `images/<UUID>.png` (the atomic write), then one GRDB row goes in at SQLite's default durability (WAL, no `synchronous`/`fullfsync` PRAGMAs; `secure_delete` stays). The thumbnail is a cache after the row. Commit points: `imageStaged`, `imageWritten`, `rowCommitted`, `thumbnailCached`. A committed row's image is never replaced.
    - **Launch sweep:** drops a row whose image is missing (with its thumbnail and the `missingHistoryImage` diagnostic); adopts a row-less `images/<UUID>.png` whose pixels decode, with its size and dimensions from the file, its date from the file's modification date and revision 1 (the file carries no revision, and a sidecar is what this ticket removes); removes everything else in `images/` and `thumbnails/` that no row owns, and any `staging/`. So a crash between the PNG and the row keeps the capture, visibly, after the next launch.
    - **Eviction:** one batch per enforcement (age, then oldest-first for the quota): record the quota event, unlink image then thumbnail for every entry, remove all rows in one transaction, one checkpoint. Files go before rows, so a crash leaves rows with missing images (dropped by the sweep), never an orphan PNG the sweep would adopt back. Eviction points: `filesUnlinked`, `rowsRemoved`.
    - **Retired:** the sidecar JSON, the auxiliary ledger, the `deleting` state, `staging/`, the `F_FULLFSYNC` and directory-fsync chain, and the flock with its 250 ms D27 retry. `HistoryFailure.rootLocked` and its diagnostic code are removed (retired term). Two stores on one root are safe at the SQLite level; the worst case is a sweep adopting another store's image just before its row, which that commit reports as `recoveryRequired`.
    - **Migration:** `history-rows-v1` rebuilds `history` without the sidecar columns and drops the ledger. Before it runs, the database is backed up into `migration-backup/` (inside the excluded root and excluded itself), and the files of rows the old store was deleting are unlinked. The migration checks inside its own transaction that every finalized row survives with a canonical identifier, then `integrity_check` must pass; only then are `staging/`, the sidecars and the backup deleted. A failed migration rolls back and keeps the backup. Queries never write, so an unmigrated database reports `recoveryRequired` until the launch sweep migrates it.
    - **Why:** plan §1 O5 and DA-11: SQLite transactions are crash-durable at default settings, and Snapzy and Capso keep rows plus a launch sweep. D27 (the flock seen as held just after close while child processes started) and D24 (recovery and drag staging sharing `staging/`, and a double count after a finalize crash) go with the mechanisms that caused them.

75. **Editor preview from the Capture renderer (implementer, 2026-09-25, ticket 68; decisions 54, 57, 61 and 70):**
    - **Interface:** `CaptureRenderer.preview(_ capture: Data, maxEdge: 2048) throws(RenderFailure) -> CapturePreview` decodes the capture once; `CapturePreview.render(edits) -> CGImage` takes the same `DocumentEdits` as Done and paints with the same internal function as `flatten` (`EditPainter.paint`). With no downscale (the capture's longer edge at most `maxEdge`) it equals the decoded `flatten` output byte for byte. A crop does not change the preview's scale: a cropped output that fits in `maxEdge` from a larger capture is still shown downscaled.
    - **Downscaling (D23):** preview pixel `j` stands for the capture block `[j·W/w, (j+1)·W/w)`, so non-integer reductions are allowed. Each preview pixel is a vImage box average of capture pixels centred in its block and no wider than it, so it mixes in no pixel from outside its block. Rejected: ImageIO thumbnails and Lanczos (`vImageScale`), whose kernels reach into neighbouring blocks and could mix in content from under a redaction; rendering at full size and then shrinking (per edit, about 670 MB at the DA-6 cap). Redactions, effect boxes and the crop are snapped in output pixels, then mapped to every preview pixel they touch. So every block touching a Solid redaction is exactly its colour at alpha 255 (decision 61), and no preview pixel shows content from under it. Annotations draw under a scaling transform, so strokes, arrow heads and labels keep their full-size geometry. Glyph subpixel quantization is turned off when the preview is downscaled, because it moved labels up by one preview pixel. Blur and Magnify run on the preview's pixels, inside their mapped box, so their strength is only approximate when downscaled.
    - **Off the main actor:** `CaptureSurfaces` builds the preview and decodes Thumbnails with `@concurrent` functions. `EditorWindow` renders the latest edits in a `@concurrent` function, one render at a time; edits made during a render are rendered next. The main actor only swaps the finished image in. History's thumbnail loader was left as it is, because it is ticket 78's code.
    - **Measured (release, this Intel Mac, `editorPreviewOpensAndRendersEachEdit`):** 6,016 × 3,384: open 0.25 s, 2,048 × 1,152 preview, slowest render with every edit kind 27 ms. 5,120 × 32,768: open 2.0 s, 320 × 2,048 preview, slowest render 12 ms. `RenderTimingTests` also holds `preview` and `render` under 250 ms at 800 × 1,000 px in debug.
    - **Deleted:** `DocumentRenderer`'s public API and its strip walk (`forEachStrip`, `concatenate`, whose D1 strip tests are replaced by preview-versus-delivered parity tests), `EditorProxy`, `PNGBitmapCodec`, `Bitmap`, `EditorDocument` and `BitmapCodec`. The painter's working buffer is the internal `RGBABuffer`. These names are retired in `Checks/retired-terms.tsv`.

76. **Finalized Thumbnails stay; an open editor pauses the timeout (implementer, 2026-09-25, ticket 91; decisions 54, 57 and 67):**
    - **Editor:** `CaptureLifecycleCoordinator.setEditorOpen(_:for:)` is called by `CaptureSurfaces` when the editor opens and when it leaves. While it is open, that Thumbnail's timeout is paused: no `dueExit == .timeout`, no `nextDueAt` from it, and `.exitThumbnail(_, .timeout)` is refused as not due. When the editor leaves (Done, Close or a delivery), the timeout restarts in full from that moment. Overflow still applies.
    - **Kept card:** a Thumbnail whose capture History committed (after Copy, Save, drag, Done or the editor's Close) stays in the stack with status `finalized` ("Capture kept in History", no Edit or Delete) until its timeout, a Thumbnail exit (Close, swipe, Escape), overflow, quit or a History Delete. After Copy, Save, drag or Close the pixels are released as before, and the kept card delivers again from History. After Done the pixels stay in memory until the card exits, as before. `.dismiss` finalizes and keeps the card; `.exitThumbnail` and quit close it. Copy does not restart the timeout: the card keeps its arrival timeout.
    - **Why:** ticket 73 released the card together with the pixels, so a Copy closed the Thumbnail at once, and the timeout ran during editing, so Done after 10 s found nothing. The live `editor-redaction` and `history-delete` rows depended on the kept card.

77. **Editor undo through the window's undo manager (implementer, 2026-09-25, ticket 69; O11, decisions 54 and 57):**
    - **One undo manager:** FrisketCore's `UndoableEdits` holds the editor's `DocumentEdits` and registers every change with an `UndoManager` (Foundation). `EditorWindow` returns that manager from `windowWillReturnUndoManager(_:)`, so ⌘Z, ⌘⇧Z and Edit › Undo/Redo reach it through the window like in any Mac app, and label-field typing shares it. The custom `undoStack` is deleted.
    - **Named edits:** the manager groups by event, as AppKit's do, so each canvas drag (one mouse-up) is one undo step, named from what it changed: Solid Redaction, Crop, Shape, Arrow, Label, Blur or Magnify. The Edit menu reads "Undo Crop", "Redo Arrow" and so on; the toolbar Undo button's tooltip names the edit too. A drag that changes nothing registers nothing; a new edit after an undo clears Redo.
    - **Unchanged elsewhere:** Undo and Redo do nothing while the editor is finishing. Closing asks only when the current edits differ from none, so undoing every edit makes Esc and Close close without asking, as before.
    - **Why:** plan O11: the custom stack had no Redo, no menu names, and could drift from the menu's enabled state. The editor has no document architecture, so a plain `UndoManager` returned by the window delegate is the smallest native route; it stays in the core so every edit kind is tested there.

78. **Restore to Thumbnail reuses the kept card (implementer, 2026-09-25, ticket 79; DA-10, decisions 28, 54, 57 and 76):**
    - **Command:** `CaptureCommand.restoreFromHistory(id)` looks the row up with `finalizedImage`, marks the capture finalized at History's revision, and puts it back in the stack as a kept card (this ticket's outcome `.restored(revision)`). No pixels come back into memory: Copy, Save, drag and Copy Text read from History, as on any kept card after decision 76, and Edit is absent because the card is finalized.
    - **No second row:** a restored card leaves by timeout, Close, swipe, Escape, overflow or quit through the kept-card path, which never commits. `.dismiss` is refused as already finalized.
    - **Again:** restoring a capture whose card is still listed keeps the one card and restarts its timeout in full. A pending capture has no row, so it can't be restored (`unknownCapture`), and nor can a deleted one.
    - **Delete:** History Delete closes the restored card, as it does any kept card.
    - **App:** the History window gains one row action, "Restore to Thumbnail" (Return). The card's preview is decoded from History's image, and it opens on the pointer's display.

79. **Dated export names, a Save confirmation and ⌘⇧ order (implementer, 2026-09-25, ticket 81; D15–D17, decisions 54 and 57):**
    - **Export names:** `Frisket 2026-09-25 at 14.03.07.png`, macOS screenshot style, in local time at the moment of the save; a collision adds ` (2)`, ` (3)` …. Dots, not colons, because Finder shows a colon as a slash. The capture ID and revision are no longer in the name (`Frisket-<UUID>-rN.png`). The save moment, not the capture moment, names the file: the export is a new file made then, a History row Save of an old capture is dated when it was saved, and the finalization carries no wall-clock time. `PNGFileExporter` takes `now` and `timeZone` for tests. A dragged-out file gets the same name (it was `Capture.png`); the drop target resolves collisions.
    - **Save confirms:** `Notice.after` returns `Notice.saved(filename)` ("Saved. <name> is in the export folder.") for a Save or Retry Save that History kept or that is over the History size limit (that notice wins). It shows on the notice line, never a modal. History row Save shows it too.
    - **⌘⇧ order:** wherever Frisket writes a shortcut, modifiers read Control, Option, Command, Shift (`ShortcutBinding.modifierSymbols`), so Command–Shift reads ⌘⇧ (story 101). Menu key equivalents are drawn by macOS in its own fixed order (⇧⌘); Frisket cannot reorder those glyphs and keeps the native menu.
    - **Copy and Delete Latest:** disabled when there is nothing to act on. Copy Latest acts on the newest card, pending or kept; Delete Latest on the newest pending card (`Thumbnails.latestToCopy`, `latestToDelete`).
    - **Windows:** History and Settings open centred on the display under the pointer (the D14 rule the notice line already uses) unless already open there. Settings opens with no text field focused, so the auto-dismiss field no longer takes first focus.
    - **About:** the notices show as headings, formatted paragraphs and monospaced licence texts (`AboutContent.noticeBlocks`), not Markdown source. The notices file no longer cites a decision number.
    - **Thumbnail picture:** the image well is an accessibility element with the image role, named "<Pending capture | Capture kept in History> preview".

80. **The app links FrisketAdapters; one preference-key enum (implementer, 2026-09-25, ticket 77; O13 step 2, decisions 54 and 57):**
    - **Build graph:** `Package.swift` exposes `FrisketAdapters` as a static library product. The app links it next to `FrisketCore`, and the synchronized `Frisket` folder lists every `Adapters/*.swift` file in the app target's membership exceptions, so no adapter file compiles in the app. Xcode ignores a bare `Adapters` folder name there (tried: the app still compiled all 19 files), so a new adapter file must be added to the list; the alternative, moving the adapters to `Sources/`, would rename a path the project rules and parallel tickets use. The `app-sources` repository check fails if either link breaks. Only what the app calls is `public`; test seams (the synthetic-content `ScreenCapturePlatform` initializer, the drag write injection) stay internal and are reached with `@testable import`. The four `@preconcurrency import ScreenCaptureKit` lines go: the macOS 26 SDK builds clean without them.
    - **Preference keys:** `PreferenceKey` in FrisketCore is the one list of stored defaults names; the raw values are the names already on disk, so no setting is lost. `ThumbnailAutoDismissPreference.neverKey`/`secondsKey` and `OnboardingCompletion.preferenceKey` go.
    - **Shortcut migration:** the ⌃⌥⌘ defaults never shipped, so `legacyDefaultBinding` and the migration in `ShortcutCommands.resolved(saved:)` go. A saved ⌃⌥⌘ shortcut is now kept as the user's choice.
    - **History reads:** a row or usage value History can't decode is `HistoryFailure.unavailable` (GRDB's throwing `decode`), not a trap from a force unwrap or GRDB's non-optional subscript.
    - **Sendable:** the stitcher and scrolling session the plan named went with ticket 87; no `@unchecked Sendable` or actor-confined `Sendable` type is left, so nothing changes.

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
