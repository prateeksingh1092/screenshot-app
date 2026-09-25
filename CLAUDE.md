# Frisket

A menu-bar screenshot app for macOS 26 (Swift 6). The code has three parts:
- `Sources/FrisketCore`: the pure core;
- `Frisket/Adapters`: AppKit, ScreenCaptureKit and Vision adapters;
- `Frisket/`: the app.

These rules apply to every agent working in this repository.

## Sources of truth

Work from these, highest authority first:

1. The user's instructions in the current session.
2. `.scratch/screenshot-mvp/decisions.md`: accepted product decisions. Record a new or amended decision there before writing code that depends on it.
3. `Plans/dreamy-giggling-barto.md`: the current remediation plan. Run its phases in order and stop at each gate. Its DA-n proposals become rules only once they are recorded in `decisions.md`. To resume interrupted work, start from `Plans/2026-09-24-session-handoff.md`.
4. `CONTEXT.md`: the domain language. Name modules, tests and UI text with its terms.
5. `.scratch/screenshot-mvp/spec.md` and `issues/`; `docs/` (ADRs are in `docs/adr/`); `.scratch/visual-pass/` for the locked visual route.

The working set is everything outside `archive/`. `archive/` holds provenance only: leave it unread unless the user names a file in it.

## Invariants

Every change keeps these true:

- **Pending capture:** its pixels stay in memory until an authorized finalization. Nothing about it reaches disk earlier.
- **Solid redaction:** every redacted pixel is exactly the user's chosen colour at alpha 255 (default black, decision 61), in every output: clipboard, file, drag, History, Thumbnail and OCR input.
- **Delivered image:** it matches the editor preview; what the user saw is what they get.
- **The core:** FrisketCore does no disk I/O and imports only what `Checks/check_repository.py` allows. No module uses network APIs.
- **Clipboard:** writes are marked concealed and current-host-only.

## Workflow

- **Technical choices are yours to make.** Prateek delegates them (decisions 54 and 57): vet the options against evidence, apply the best-supported one, and record it in `decisions.md`. Bring him only product-visible trade-offs, explained in plain language with a recommendation.
- **Test first, at the production seam.** Test through the interface real callers use: `CaptureLifecycleCoordinator.execute` for the capture lifecycle, the save-path renderer for edits, `WindowSelection` for window picking. Write the test, watch it go red, then fix.
- **Before calling work done,** run `scripts/ci.sh`: the repository checks, the package tests and the unsigned app build. A test that reproduces an open defect is wrapped in `knownDefect("Dn")`; a fix deletes the wrapper. Build and install steps are in `docs/app-build.md`.
- **Live checks** use the synthetic patterns from `Tools/FrisketTestPattern.swift`. Capture only synthetic content, and restore the user's clipboard after driving the app.
- **Triage failures in one pass.**
  1. Read the evidence of every failed row before rerunning any of them.
  2. Sort each failure into a harness fault or a Frisket defect.
  3. Set a time limit, and tell Prateek what it is. A harness run lasts 9 minutes at most per display, and a user test 15 minutes; `beta-matrix.sh` enforces the 9 minutes (decision 66).
  4. At the limit, record the results and list what is still open. Tell Prateek before the scope grows.
- **Record Prateek's decisions** from chat in `decisions.md` in the same turn, before any code. If a decision retires a term, add the term to `Checks/retired-terms.tsv`; `ci.sh` then fails if a live file still uses it.
- **Commit messages** record the model and effort level that produced the change.
- **Billing:** only the user's existing included allowances (decision 9).
- **Lead agent:** decisions 7, 8 and 11 name Codex as lead and Cursor's Claude Opus 5.5 as the complement. Plan item DA-7 proposes changing that. Until it is recorded, the user's in-session instruction decides who leads.

## Process skills

The project's process uses Matt Pocock's skills: `tdd`, `diagnosing-bugs`, `code-review`, `codebase-design`, `domain-modeling` and `improve-codebase-architecture`. They come from the `mattpocock-skills` plugin, or from the copies in `.cursor/skills/matt-pocock/`. Follow a skill's own `SKILL.md` rather than reconstructing its steps.
