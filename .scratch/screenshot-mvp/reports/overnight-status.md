# Overnight status (running log for Prateek)

Updated: 2026-09-23 02:40 CDT. The Cursor agent is the only coordinator and integrator. Since 02:22 the implementers come from three pools: Codex (GPT-6 Astra, high), Grok 4.7 High (`grok-4.7-high` via the Cursor CLI) and Claude Opus 5.5 High (`claude-opus-5-5-high` via the Cursor CLI). Every report and review names its model. Both Cursor CLI models passed a read-only smoke test at 02:24.

## Merged to `main`

| Ticket | Result | `main` SHA (merge) |
|---|---|---|
| 34: stitcher adoption | Stitcher moved into the core and the trial was removed. 51 tests pass; the review found nothing. | `c2c764e` |
| 08: real area capture to Copy | First signed app. Fix pass: Copy focus, an sRGB test pattern, and a single-hot-key check. 58 tests pass; the unsigned build works. | `ad2b253` |
| 41: app target as a synchronized folder | Build-hygiene ticket created on your 01:05 directive. The review found nothing. | `7c1b87d` |
| 37: performance tooling | Measurement scripts and runbook. Fix pass: arming, cooldown stalls, a shared parser. 59 tests pass. | `c49b958` |
| 20: full-screen capture | Menu item only; the shortcut belongs to ticket 24. Seam 1 covers 1×, 2× and negative coordinates. | `58f0b2f` |
| 19: selection precision | Core `SelectionGeometry`, Shift+arrow resize, a magnifier, and a shared `ScreenCapturePolicy`. | `3f86bf6` |
| 09: dismiss finalizes into History | GRDB 7.11.1 is pinned exactly. File-first commit with nine named commit points. Fix pass: a History-failure notice and Delete hidden after a failed Copy delivery. Codex resolved the integration conflicts with 19 and 20, so full-screen captures also go to History. 80 tests pass; the unsigned build works. | `02b2864` |
| 23: permission states and recovery | The core `CapturePermissionPolicy` has five states. Permission is checked before any overlay. Quit & Reopen uses `/usr/bin/open -n` with no shell. Codex resolved the integration with 09: Quit finalizes before relaunching. 97 tests pass; the unsigned build works. | `992a511` |

## In flight

| Pool | Ticket | Stage | Started |
|---|---|---|---|
| Codex | 18: selection overlay across displays | Fix pass (Space tracking) | 02:37 |
| Codex | 10: launch recovery sweep | Implementing | 02:14 |
| Codex | 11: Save and the Settings shell | Implementing | 02:14 |
| Grok 4.7 High | 12: drag handoff | Implementing | 02:30 |
| Grok 4.7 High | 35: scrolling capture | Implementing | 02:30 |
| Opus 5.5 High | 13: thumbnail stack and Delete | Implementing | 02:30 |
| Opus 5.5 High | 26: editor tracer (Solid redaction) | Implementing | 02:30 |

Ticket 18 is a third Codex slot for its fix pass only. It will be freed before 21 or 38 start.

**Next:**
- **Codex:** 21 (window capture) and 38 (performance targets), then 14–17 once 11 and 13 merge.
- **Grok:** 22, 24 and 25 as they unblock.
- **Opus:** the editor chain, 27–33 and 36, after 26.

**Review pairing:** Opus reviews Codex, Codex reviews Grok, and Grok reviews Opus. The ticket 18 review ran on Codex because it was launched before the 02:22 directive.

## Deferred items picked up after decision 51

- **Signed rebuild and install (02:35).**
  - Current `main` (`e505907`) was built signed with the existing identity (team `9M43Q952NK`, same bundle ID).
  - I quit the old app, moved it aside into `.build/` in the signing worktree, and installed the new build with `ditto` to `~/Applications/Frisket.app`.
  - `codesign --verify --strict` reports it valid and satisfying its designated requirement. The hardened runtime is on, and the entitlements are an empty dictionary.
  - The designated requirement is byte-identical to the previous build's (same SHA-256), so the Screen Recording grant should carry over. Confirming that is still your manual check.
  - The installed app is running. It created no History root at launch, which confirms ticket 09's "nothing written before finalization" on a real install.
- **Snapzy build.** `bash Tools/Performance/build-snapzy.sh --coordinator-build` is running into `.build/snapzy-baseline/`, which is gitignored scratch. The clone stays read-only.
- **Ticket 37's automatable baselines.** These wait for the Snapzy build.
- **`tmutil isexcluded`** needs a finalized capture first. It stays pending until you do a synthetic Dismiss; running it takes one command afterwards.

## Pending manual items (need you)

- **Ticket 08:** see `docs/manual-checks/08-first-launch.md`.
  - Colour rerun. The blue measured 22,0,255 before the fix that made the test pattern draw in sRGB.
  - Keyboard Copy with Tab and Space, the focus outline, and VoiceOver.
  - Drag selection, the display-edge clamp, and Esc without activating Frisket.
  - ⇧⌘3/4/5/6 still belonging to macOS.
  - Capture on the external display.
  - The grant surviving signed rebuilds. The requirement is now proven identical across one rebuild; the grant itself still needs checking.
- **Ticket 20:** full-screen capture from the menu on each display, using the synthetic test pattern only.
- **Ticket 19:** see `docs/manual-checks/19-selection-precision.md`.
  - Arrow and Shift+arrow nudging.
  - The magnifier.
  - The clamp at the display edge.
- **Ticket 09:**
  - Synthetic Dismiss, and the "Kept in History" feedback.
  - Persistence after Esc and after Quit.
  - VoiceOver.
  - Delete behaviour.
  - Backup exclusion of the `.noindex` root, checked with `tmutil isexcluded`.
- **Ticket 23:** in an isolated account, per `docs/manual-checks/23-permission-states.md`:
  - each of the five states;
  - the ordering against the native alert;
  - Quit & Reopen;
  - behaviour after re-signing.
- **Ticket 34:** a few recorded real scroll sequences with no personal content.
- **Ticket 37:** the live baselines that need eyes or keyboard, and confirming the GPU.

## Your decision queue

1. Ticket 41 was created by the coordinator, on your directive, for build hygiene only. No action is needed unless you object.
2. The earlier questions about allowlisting commands and approving Snapzy launches are settled by decision 51.

## Process notes

- The first ticket 08 fix-pass launch failed because shell redirections pushed Codex into Cursor's sandbox. The launch form is now documented in `docs/agents/implementation-workflow.md` (Toolchain).
- The forked coordinator started at 23:54 never did any work; the main coordinator took over tickets 08 and 34 at 00:45.
- Codex resolved the integration merges for tickets 09 and 23 in fresh sessions, following the resolving-merge-conflicts skill. The coordinator verified each one outside the sandbox before fast-forwarding `main`.
