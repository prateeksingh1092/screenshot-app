# Implementation workflow

How Frisket tickets are implemented under decision 46. Grounded in [the Pocock implementation research](../research/2026-09-22-pocock-implementation-process.md); Codex assesses changes to this file.

## Per ticket

1. The coordinator picks tickets from the frontier: open tickets whose blockers are all resolved.
2. Each ticket gets its own worktree and branch, `ticket/NN-slug`, created from `main`. Never run two implementers in one checkout. Don't use `git stash`; the stash is shared across worktrees.
3. A fresh Codex session (GPT-6 Astra, high) runs the local `implement` skill on that one ticket: TDD at the seams agreed in the spec, typecheck and single test files often, full suite once at the end, then commit to the ticket branch.
4. The implementer doesn't change the ticket's status or checkboxes. It reports what it did, and that report becomes a `## Comments` entry.
5. A separate fresh Codex session runs `code-review` with the ticket's merge-base as the fixed point. Both reviewer briefs include: "Do not invoke `/code-review` or spawn additional agents." Findings are leads, not evidence. The implementer fixes them in one pass; the review isn't looped until it comes back clean.
6. The coordinator checks that the work adheres to this workflow and the ticket, merges the branches into `main` one at a time, re-runs the full suite on `main`, then ticks criteria, sets `Status: resolved`, and removes the worktree.

## Gates

- Prateek approves the actions that decision 46 still gates.
- Tickets marked `ready-for-human` wait for Prateek.
- Anything that needs Xcode waits until Prateek reports it installed.
- Stop at included-usage limits and report them.

## Periodically

Run `improve-codebase-architecture` every few merged tickets, outside any ticket chain. File its proposals as new tickets through `triage`.

## Not adopted

Upstream's beta `implement-spec` skill and Sandcastle are references only. Sandcastle needs Docker and API-key-style authentication, which conflicts with the billing policy.

## Transitional note

Tickets 01 and 02 ran in one checkout before this workflow existed. Ticket 01 was committed on `main` as `a7f3e0b`, without ticket 02's files. Ticket 02 is reviewed against `a7f3e0b` in a fresh session.
