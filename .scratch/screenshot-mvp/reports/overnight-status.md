# Overnight status (running log for Prateek)

Updated: 2026-09-23 02:15 CDT. The coordinator is the Cursor agent; implementers and reviewers are Codex, GPT-6 Astra (high), unless noted otherwise.

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

## In flight

- **23: permission states and recovery.** The review returned fix-then-merge: move the state policy into the core, and remove `/bin/sh` from Quit & Reopen. The fix pass is running.
- **18: selection overlay across displays.** Codex implementer running since about 02:00.
- **10: launch recovery sweep.** Codex implementer launched 02:14.
- **11: Save and the Settings shell.** Codex implementer launched 02:14.
- **Next:** 21 (after 18), then 12, 13, 26, 35 and 38. Ticket 11 unblocks 14–17, 22 and 24.

## Pending manual items (need you)

- **Ticket 08:** see `docs/manual-checks/08-first-launch.md`.
  - Colour rerun. The blue measured 22,0,255 before the fix that made the test pattern draw in sRGB.
  - Keyboard Copy with Tab and Space, the focus outline, and VoiceOver.
  - Drag selection, the display-edge clamp, and Esc without activating Frisket.
  - ⇧⌘3/4/5/6 still belonging to macOS.
  - Capture on the external display.
  - The grant surviving two signed rebuilds.
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
- **Ticket 34:** a few recorded real scroll sequences with no personal content.
- **Ticket 37:** the Snapzy unsigned build, then the live baselines from `docs/manual-checks/37-performance-baselines.md`. Snapzy and the macOS tool must be launched and must capture, which decision 50 doesn't cover. The GPU also needs confirming.

## Deferred (needs a command outside the allowlist)

- **Snapzy build.** From the repository root on `main`, run `bash Tools/Performance/build-snapzy.sh --coordinator-build`. It stopped at an approval prompt at 01:12. The partial output was removed with the ticket-37 worktree.
- **Signed rebuild and install of the current `main` app.** This needs `codesign` and `ditto`, so `~/Applications/Frisket.app` is still the pre-fix ticket 08 build. Build with the signed command in `docs/app-build.md`, then install as that document describes.

## Your decision queue

1. Ticket 37: approve launching Snapzy and the macOS screenshot tool for the baseline runs, and confirm the GPU.
2. Whether to allowlist `bash`, `ditto` and `codesign` for the coordinator, or keep deferring those steps to you.
3. Ticket 41 was created by the coordinator, on your directive, for build hygiene only. No action is needed unless you object.

## Process notes

- The first ticket 08 fix-pass launch failed because shell redirections pushed Codex into Cursor's sandbox. The launch form is now documented in `docs/agents/implementation-workflow.md` (Toolchain).
- The forked coordinator started at 23:54 never did any work; the main coordinator took over tickets 08 and 34 at 00:45.
