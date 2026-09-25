# Implementer brief: Frisket Phase 1 tickets

You fix one or more tickets in Frisket, a Swift 6 menu-bar screenshot app for macOS 26. For each ticket named in your task:

- The ticket file is `.scratch/screenshot-mvp/issues/<NN>-<slug>.md`.
- Its worktree is `/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-<NN>`, on branch `ticket/<NN>-<slug>`, already checked out, with `.build` caches seeded.

Work only inside that worktree: absolute paths, and `cd` into it for commands. Never edit the main checkout or another worktree.

## Read first, in the worktree

1. `CLAUDE.md` (the project rules and invariants).
2. The ticket file, including its Comments.
3. `CONTEXT.md` (the domain terms).
4. Decisions 57 and 58 at the end of `.scratch/screenshot-mvp/decisions.md`.

## How to work (test first)

1. Each defect the ticket names already has a red test, wrapped in `knownDefect("Dn")`. Find it with `grep -rn 'knownDefect("Dn")' Tests`, then run it with `scripts/test-core.sh --filter '<name>'`. It passes today as a known issue.
2. Delete the `knownDefect` wrapper and keep the body. Run the test and watch it go red for the reason it names.
3. Fix the product code at the production seam the ticket names, so the test goes green. Keep the change as small as the ticket allows. Don't refactor beyond the ticket.
4. If an existing test locks in the old, wrong behaviour, change it, and say so in your report.
5. Add a test for each other acceptance criterion that a package test can reach. Criteria marked as live-matrix rows are checked later by the coordinator; don't try them.
6. **Long commands run in the background.** `scripts/test-core.sh` takes about 1 minute when warm. The first build in a worktree takes about 4–6 minutes. Run it in the background with output to a log file, and read the log when it ends. Never block for more than 10 minutes.
7. At the end, `scripts/ci.sh` must print `ci: green`. `scripts/ci.sh --defects` must no longer list the defect you fixed.

## Don't

- Launch Frisket, capture the screen, or use the clipboard.
- Run the live harness.
- Sign, install, push or merge.
- Touch `main`.
- Use network APIs; the repository check forbids them.

## Finish

1. Tick the criteria you met in the ticket file, and leave live-matrix criteria unticked.
2. Append `### 2026-09-24: implementer, report` to the ticket file. It records the model and effort (Claude Opus 5.5, high), what changed and why, the tests, and anything left open.
3. Commit on the ticket branch. The message ends with this line and the trailers:

   ```
   Model: Claude Opus 5.5 (1M context), Claude Code, high effort.

   Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
   Claude-Session: https://claude.ai/code/session_01SsxjzzJbhgsFqwBv3tvTfP
   ```

4. Reply in under 200 words: files changed, tests (red → green), the `ci.sh` result, and anything the coordinator must check live.
