# Overnight status (running log for Prateek)

Updated: 2026-09-23 01:25 CDT. The coordinator is the Cursor agent; implementers and reviewers are Codex, GPT-6 Astra (high), unless noted otherwise.

## Merged to `main`

| Ticket | Result | `main` SHA |
|---|---|---|
| 34: stitcher adoption | Stitcher moved into the core and the trial was removed. 51 tests pass; the review found nothing. | `c2c764e`, closed in `1f75e50` |
| 08: real area capture to Copy | First signed app. Fix pass: Copy focus, an sRGB test pattern, and a single-hot-key check. 58 tests pass; the unsigned build works. | `ad2b253`, closed in `07c9daf` |

## In flight

- **37: performance baselines.** Review verdict fix-then-merge. The fix pass is running.
- **41: app target as a synchronized folder.** A new build-hygiene ticket, created on your 01:05 directive; rationale in the ticket. Implemented; review running.
- **Next batch:** tickets 09, 19 and 20 start after 41 merges; tickets 18, 21 and 23 follow.

## Pending manual items (need you)

- **Ticket 08:** see `docs/manual-checks/08-first-launch.md`.
  - Colour rerun. The blue measured 22,0,255 before the fix that made the test pattern draw in sRGB.
  - Keyboard Copy with Tab and Space, the focus outline, and VoiceOver.
  - Drag selection, the display-edge clamp, and Esc without activating Frisket.
  - ⇧⌘3/4/5/6 still belonging to macOS.
  - Capture on the external display.
  - The grant surviving two signed rebuilds.
- **Ticket 34:** a few recorded real scroll sequences with no personal content.
- **Ticket 37:** live baselines, run from `docs/manual-checks/37-performance-baselines.md`. Snapzy and the macOS tool must be launched and must capture, which decision 50 doesn't cover.

## Deferred (needs a command outside the allowlist)

- **Ticket 37's Snapzy unsigned build.** The command is `bash Tools/Performance/build-snapzy.sh --coordinator-build` in the ticket-37 worktree. It stopped at an approval prompt and was interrupted, so a partial `.build/snapzy-baseline/` may be left in the ticket-37 worktree. The script refuses to run while that folder exists: delete it, then rerun the command.
- **Signed rebuild and install of the fixed ticket 08 app.** This needs `codesign` and `ditto` outside the allowlist, so `~/Applications/Frisket.app` is still the pre-fix build.

## Your decision queue

1. Ticket 37: approve launching Snapzy and the macOS screenshot tool for the baseline runs, and confirm the GPU.
2. Whether to allowlist `bash`, `ditto` and `codesign` for the coordinator, or keep deferring those steps to you.
3. Ticket 41 was created by the coordinator, on your directive, for build hygiene only. No action is needed unless you object.
