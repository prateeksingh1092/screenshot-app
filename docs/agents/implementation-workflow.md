# Implementation workflow

How Frisket tickets are implemented under decision 46. Sources: the local `implement`, `tdd`, and `code-review` skills (requirements), [the Pocock implementation research](../research/2026-09-22-pocock-implementation-process.md), and Codex's assessment (adopt with changes, 2026-09-22). Two practices here come from Matt Pocock's upstream docs, not from the local skill text, and are adopted as project practice: review in a fresh session, and the operator (not the implementer) closes tickets.

## Per ticket

1. **Claim.** The coordinator picks a ticket from the frontier: an open ticket whose blockers are all `resolved`. It sets `Status: in-progress` and records the branch name.
2. **Isolate.** Each ticket gets its own worktree under `.worktrees/` and a branch `ticket/NN-slug`, created from current `main`. Never run two implementers in one checkout, and don't use `git stash` (the stash is shared across worktrees).
3. **Implement.** A fresh Codex session (GPT-6 Astra, high) runs the local `implement` skill on that one ticket. That means TDD red→green at the seams the spec agreed, with typecheck and single test files run often, and the full suite once at the end. The implementer stops before review and doesn't change the ticket's status or checkboxes. Its report becomes a `## Comments` entry.
4. **Freeze.** The coordinator commits everything the implementer produced (staged, unstaged, and untracked) to the ticket branch as a review snapshot. Commits on a ticket branch are review snapshots; decision 46's "commits after review" applies to `main`. This lets `code-review` see the exact content under review via `<merge-base>...HEAD`.
5. **Review once.** A separate fresh Codex session runs `code-review` with the merge-base as the fixed point. Every reviewer brief says: "Do not invoke `/code-review` or spawn additional agents."
6. **Fix.** Codex validates each finding against the code. It fixes the justified ones in one pass as new commits on the ticket branch, reruns the affected checks and the full suite, and records any finding left open, with the reason. Don't relaunch broad reviews just to get zero findings. An unresolved correctness failure blocks the merge.
7. **Integrate.** The coordinator merges the ticket branch into a fresh integration branch cut from current `main` and runs the full suite plus the static checks there. Only a green result is fast-forwarded into `main`. Integrate one ticket at a time.
8. **Close.** The coordinator ticks the criteria and records the tested `main` commit and the verification report. It then sets `Status: resolved` and removes the worktree and the merged branches.

## Toolchain

Pass `DEVELOPER_DIR` explicitly on every command. Swift tests use Xcode 26.5's toolchain, because the Command Line Tools lack Swift Testing (decision 47).

Launch Codex from Cursor without shell redirections. Pass the brief's absolute path as the prompt argument, use `-o <file>` for the final message, and request `required_permissions: ["all"]`:

```sh
codex exec -m gpt-6-astra -c model_reasoning_effort='"high"' -c sandbox_mode='"workspace-write"' \
  -C <worktree> -o /private/tmp/screenshot-app-impl/<name>-out.md \
  "Read the file <absolute brief path> and carry out its instructions exactly. It is your complete brief."
```

With redirections (`<`, `>` or `2>`), a command no longer matches Cursor's allowlist and falls back to Cursor's sandbox. Codex then fails with "Operation not permitted". The same applies to commands that start with a variable assignment or `sh`. Set environment variables with `export` in an earlier shell call instead. If Codex is unreachable or out of included usage, use Cursor Task subagents with the model `claude-opus-5-5-high`, and record which model produced each result.

### Implementer pools (from 2026-09-23 02:22)

There are three pools, each with at most two concurrent tickets, one ticket per worktree. The coordinator alone freezes, integrates and closes.

- **Codex** uses the form above.
- **Grok 4.7 High** and **Claude Opus 5.5 High** run detached through the Cursor CLI, always invoked by its explicit path:

```sh
/Users/16intelmac/.local/bin/cursor-agent -p --model <grok-4.7-high | claude-opus-5-5-high> --force --trust \
  --workspace <worktree> --output-format text "Read the file <absolute brief path> and carry out its instructions exactly. It is your complete brief." > <log> 2>&1
```

Because `--force` is set, the brief also forbids:
- any git command;
- writes outside the worktree;
- signing, installs, launches, screen capture and clipboard use.

A reviewer never shares the implementer's model: Opus reviews Codex, Codex reviews Grok, and Grok reviews Opus. The fix pass is a fresh session of the implementer's model. Text output appears only at exit, so judge progress by worktree changes and elapsed time.

## Gates

- Prateek approves the actions that decision 46 still gates.
- Tickets marked `ready-for-human` wait for Prateek.
- Stop at included-usage limits and report them.

## Periodically

Every few merged tickets, run `improve-codebase-architecture` outside any ticket chain. Its proposals go to Prateek to select and grill, then through spec and tickets as usual. They are never ticketed automatically.

## Not adopted

Upstream's beta `implement-spec` skill and Sandcastle are references only. Sandcastle needs Docker and API-key-style authentication, which conflicts with the billing policy.

## Transitional note

Tickets 01 and 02 ran in one checkout before this workflow existed. Ticket 01 is on `main` (`a7f3e0b`). Ticket 02 was frozen on `ticket/02-core-package` and is reviewed against `d03f009`.
