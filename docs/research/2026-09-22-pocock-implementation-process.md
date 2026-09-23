# Pocock's process after to-spec and to-tickets

Requested model: Claude Opus 5.5, high effort, through native Cursor.
Status: research only, pending Codex and Prateek assessment. Nothing here is an accepted decision.

Sources are Matt Pocock's own repositories and his aihero.dev articles. Skill links point at upstream `main` commit [`c55ee46`](https://github.com/mattpocock/skills/commit/c55ee46073ed923f86ce59a5eb3b6d895095d1b7) (2026-09-18). "Stated" means he wrote it. "Inference" means I concluded it.

## Summary

- **Stated:** one ticket per fresh session. Each run reads the ticket, uses TDD at the seams agreed in advance, typechecks and runs single test files often, runs the full suite once, runs `code-review`, and commits to the current branch ([implement docs](https://github.com/mattpocock/skills/blob/c55ee46/docs/engineering/implement.md)).
- **Stated:** `implement` never updates the ticket. Closing it and ticking its criteria is the operator's job, and the frontier (the set of tickets whose blockers are all done) only moves when blockers are closed (same page).
- **Stated:** running several `/implement` sessions in one checkout is "worse than unsupported". His recommended parallel shape is one worktree and branch per ticket, then a merge step: see the in-progress [`implement-spec`](https://github.com/mattpocock/skills/blob/c55ee46/skills/in-progress/implement-spec/SKILL.md) skill and [Sandcastle](https://github.com/mattpocock/sandcastle/blob/e99f832/README.md).
- **Stated:** `code-review` diffs `<fixed-point>...HEAD`, so it cannot see uncommitted work. He recommends running it in a fresh session rather than the one that wrote the code ([code-review docs](https://github.com/mattpocock/skills/blob/c55ee46/docs/engineering/code-review.md)).
- **Observed:** our local "1.2.3" skill files are byte-identical to upstream `main`, not to the `v1.2.3` tag.

## The post-ticket workflow, step by step (stated unless marked)

1. **Dispatch.** "Dispatch is manual: look at the board, count the tickets with no open blockers, and open that many agent sessions. One ticket per fresh context" ([to-tickets docs](https://github.com/mattpocock/skills/blob/c55ee46/docs/engineering/to-tickets.md)). Clear context between tickets ([ask-matt](https://github.com/mattpocock/skills/blob/c55ee46/skills/engineering/ask-matt/SKILL.md)). Tickets produced by `to-tickets` must not be run through triage (same).
2. **Check you are on the right branch.** `implement` "commits to the branch you are on. It does not create one" ([implement docs](https://github.com/mattpocock/skills/blob/c55ee46/docs/engineering/implement.md)).
3. **Seams.** Nothing inside `implement` agrees the seams. Either the spec names them or `tdd` asks at the start. "If it happens nowhere… the run quietly becomes 'just write the code'" (same).
4. **TDD.** Red then green, one vertical slice at a time. The refactor step was removed in June 2026 because "agents essentially never performed it"; refactoring now belongs to `code-review` ([tdd docs](https://github.com/mattpocock/skills/blob/c55ee46/docs/engineering/tdd.md)). He advises writing browser and end-to-end tests after the behaviour works, not first (same).
5. **Feedback loops.** Typecheck and single test files often, the full suite once. In the Ralph loop: "Do NOT commit if any feedback loop fails" ([Ralph tips](https://www.aihero.dev/tips-for-ai-coding-with-ralph-wiggum)).
6. **Review.** Two axes, Standards and Spec, run as parallel sub-agents. Known upstream bug: the sub-agents can re-invoke `/code-review` recursively (one report reached 50+ agents). Community fix: add "Do not invoke `/code-review` or spawn additional agents" to both briefs. Treat findings as leads, not evidence, and do not loop the review until it comes back clean ([code-review docs](https://github.com/mattpocock/skills/blob/c55ee46/docs/engineering/code-review.md)).
7. **Commit.** Ralph commits after every feature, with a message listing the task, decisions, files changed, and notes for the next iteration ([Ralph tips](https://www.aihero.dev/tips-for-ai-coding-with-ralph-wiggum); [Sandcastle implement prompt](https://github.com/mattpocock/sandcastle/blob/e99f832/src/templates/parallel-planner-with-review/implement-prompt.md)).
8. **Update the ticket.** Close it and reconcile its criteria by hand. The Sandcastle implementer is told "Do not close the issue"; the merger closes it after a successful merge ([merge prompt](https://github.com/mattpocock/sandcastle/blob/e99f832/src/templates/parallel-planner-with-review/merge-prompt.md)).
9. **Human QA.** Passing tests did not prevent a missing database table in his demo. QA findings become new backlog issues while implementation continues ([talk summary, secondary](https://ai.engineer/talks/-QFHIoCo-Ko-ai-coding-workflow)).

**Discoveries mid-implementation.** Stated:
- The spec goes stale once built. Durable learnings belong in `CONTEXT.md` and ADRs, not in an edited spec ([to-spec docs](https://github.com/mattpocock/skills/blob/c55ee46/docs/engineering/to-spec.md)).
- Missing items can be added mid-loop ([Ralph tips](https://www.aihero.dev/tips-for-ai-coding-with-ralph-wiggum)).
- `diagnosing-bugs` hands off to `improve-codebase-architecture` when no good seam exists ([ask-matt](https://github.com/mattpocock/skills/blob/c55ee46/skills/engineering/ask-matt/SKILL.md)).
- The five triage states have no "blocked" or "implemented, awaiting verification" state. Matt agrees the blocked case is real, but nothing has shipped ([triage docs](https://github.com/mattpocock/skills/blob/c55ee46/docs/engineering/triage.md)).

**Periodic architecture work.** Stated: run `improve-codebase-architecture` "every few days, outside any chain", weighted toward recently changed code. Its output is an idea, which re-enters the main flow at grilling or `to-spec` ([docs](https://github.com/mattpocock/skills/blob/c55ee46/docs/engineering/improve-codebase-architecture.md)). The in-progress [`retro`](https://github.com/mattpocock/skills/blob/c55ee46/skills/in-progress/retro/SKILL.md) stub says mechanical standards should become deterministic checks, and coding standards should be enforced by the reviewer, not the implementer.

## Parallel-agent guidance (stated)

- **`implement-spec`** (beta, excluded from the plugin, "can change or disappear without warning" per the [in-progress README](https://github.com/mattpocock/skills/blob/c55ee46/skills/in-progress/README.md)):
  - Treat the tickets as a task graph with a frontier.
  - Communicate through "context pointers" (paths to the spec, tickets, and commits) rather than copied text.
  - Run each implementer subagent "in its own worktree, on its own branch", in the background, for maximum concurrency.
  - A **merger subagent** merges each finished branch into one spec branch. New implementers start as the frontier moves.
  - Run `/code-review` once at the end; fix all findings "in a single implementer subagent", then clean up worktrees.
  - An optional exploration subagent can save notes outside the repo for later implementers.
- **Sandcastle `parallel-planner-with-review`** ([template](https://github.com/mattpocock/sandcastle/tree/e99f832/src/templates/parallel-planner-with-review)) runs this loop:
  - A planner lists the unblocked issues. It also treats overlapping files as blocking.
  - Each issue gets a deterministic branch, `sandcastle/issue-{id}`.
  - An implementer, then a one-iteration reviewer, run in a sandbox with a worktree for each branch.
  - One merger merges the branches, runs the tests, and closes the issues.
  - The whole cycle repeats up to 10 times.
- **Sandbox and model choices.** AFK agents "must be sandboxed". Sandcastle ships `codex()` and `cursor()` agent providers ([README](https://github.com/mattpocock/sandcastle/blob/e99f832/README.md)). He uses Sonnet to implement and Opus to review, with the review in a fresh context ([talk summary, secondary](https://ai.engineer/talks/-QFHIoCo-Ko-ai-coding-workflow)).
- **Ralph loop.** Start with human-in-the-loop single runs to tune the prompt, then go AFK with capped iterations (5–10 for small work) inside Docker. Do risky architectural work with a human watching; save AFK for once "the foundation is solid" ([Ralph tips](https://www.aihero.dev/tips-for-ai-coding-with-ralph-wiggum)).
- **Worktree caveat.** `refs/stash` is shared across worktrees, so worktrees alone do not make stashing safe ([implement docs](https://github.com/mattpocock/skills/blob/c55ee46/docs/engineering/implement.md)).

## Upstream vs local skills

- Every local file under `.cursor/skills/matt-pocock/` matched upstream `main` at `c55ee46` byte for byte. 48 of them differ from the [`v1.2.3` tag](https://github.com/mattpocock/skills/compare/v1.2.3...c55ee46), which is 54 commits behind. The plugin version was never bumped (`plugin.json` on `main` still says 1.2.3). So `provenance.json`'s "1.2.3" label is misleading, but the content is current.
- The upstream changes since the tag that matter for this workflow:
  - The Skill tool invocation wording was standardised (`d28dfdc`, `fcf0071`), and skills no longer call user-invoked skills (`1dab982`).
  - `implement-spec` was added (`84b5ee5`, `5b15a47`), along with the `retro` and `pr` stubs. These exist only under `skills/in-progress/` and are absent locally.
- `implement/SKILL.md` itself is unchanged since the tag.

## Recommendations for the Frisket coordinator (pending Prateek/Codex assessment)

1. **Keep the worker and review stages separate.** The current prompts forbid `git add` and `git commit`, and `main` has no commits yet. So the `code-review` step inside the worker has no fixed point and an empty diff: it cannot work as specified. Options:
   - Let the worker commit on its own ticket branch, then run `code-review` against the branch point.
   - Drop `code-review` from the worker and run it in a fresh coordinator-launched session. Upstream prefers this anyway.
2. **Use one worktree and branch per parallel ticket** (for example `ticket/02`), then merge serially under coordinator control. Do this before running more tickets in parallel. Tickets 01 and 02 share one checkout. Ticket 01's staged-diff secret review will see ticket 02's files as they are being written.
3. **Remove "red-green-refactor" from worker prompts.** The local `tdd` skill excludes refactoring from the loop.
4. **Add the recursion guard** to `code-review` sub-agent briefs.
5. **Make ticket updates a coordinator step:** set the status, tick the criteria, add a comment linking the commit. Then recompute the frontier.
6. **Put the seams in each prompt or ticket** so `tdd` does not stop to ask a person who is away (AFK).
7. **Record discoveries as new numbered tickets with `Blocked by:`**, not as edits to finished ones. Route terminology changes to `CONTEXT.md` and hard-to-reverse choices to an ADR. Do this through grilling with Prateek, not inside a worker.
8. **Schedule `improve-codebase-architecture`** after each cluster of merged tickets, for example every 5–8 tickets.
9. **Treat Sandcastle and `implement-spec` as references, not dependencies.** Sandcastle needs Docker and API-key-style auth, which the billing policy may rule out.

## Open questions

- Should Frisket work on one spec branch with ticket branches (`implement-spec` style) or commit straight to `main`?
- Who does the merging: the coordinator (Cursor) or Codex?
- Our local tracker mixes the wayfinding statuses `claimed` and `resolved` with the triage states. Should implementation tickets use a separate lifecycle, such as `in-progress` and `done`?
- Is `codex exec`'s own sandbox enough for AFK runs, given Matt's "must be sandboxed" rule?
- Should review run once per ticket, once at the end of the spec, or both? The upstream docs say both work.
