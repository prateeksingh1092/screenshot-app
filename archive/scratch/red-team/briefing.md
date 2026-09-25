# Red-team briefing: screenshot-app architecture

You are one role on a red-team panel attacking an approved plan before it becomes a specification. Your job is to find what breaks, what is missing, and what is ambiguous, from your specialty. Be adversarial but concrete: every attack must propose a testable amendment.

## Project in one paragraph

A personal-first native macOS screenshot app (CleanShot-like) for Prateek's Intel x86_64 MacBook (16 GB RAM, macOS 26.7). Later distribution is possible but not a v1 requirement. No recurring services or paid add-ons. v1 features: area/window/full-screen capture; floating thumbnail with copy/save/drag/edit; configurable shortcuts; annotation; solid redaction; local OCR; scrolling capture; local history on by default. Recording, cloud storage, and hosted sharing are deferred. No application code exists yet.

## Read these (repo root is your working directory)

1. `.scratch/screenshot-mvp/decisions.md`: all accepted decisions. **Decisions 1-12** are earlier product choices; **13-25** are the architecture round Prateek just approved. These are what you attack.
2. `CONTEXT.md`: domain glossary. Use its terms (Capture, Finalized capture, History, Solid redaction, OCR, Scrolling capture).
3. `docs/research/2026-09-22-snapzy-history-adaptation.md`: how Snapzy v1.32.3 handles capture bytes, originals, clipboard, drag, OCR, retention; forced-quit cases.
4. `docs/research/2026-09-22-snapzy-local-only-surface.md`: network and local automation surface.
5. `docs/research/2026-09-22-stack-independent-assessment.md`: stack recommendation (Swift, AppKit for overlays/editor, SwiftUI for settings, ScreenCaptureKit, Vision, Core Graphics, GRDB/SQLite).
6. `docs/research/2026-09-22-xcode-necessity-assessment.md`: toolchain evidence.
7. Snapzy source for evidence: `.scratch/evaluation/Snapzy/` (release v1.32.3, commit 837fc73d). Read-only.

Read what your role needs; you do not need every file in full.

## Rules

- **Read-only.** Do not create, edit, or delete any file. Do not build, install, launch apps, capture the screen, touch the pasteboard, or change accounts, signing, or keychain. Return your findings in your final message; the parent saves them.
- Separate **observation** (cite file:line or an official URL) from **inference**. Do not claim anything was tested.
- Obey the root `AGENTS.md` and `/Users/16intelmac/.Codex/AGENTS.md` KERNEL rules (no secrets in Markdown, no memory plugins, no reading `~/.Codex/projects/*/memory/**` or session tapes).
- Do not re-open decisions merely by preference. Attack a decision only if you can show a concrete failure, cost, or contradiction. You may propose reversing a decision, but mark it clearly.
- Stay within your specialty. Say "outside my role" rather than guessing.

## Output format (round 1)

Return Markdown, 600-1000 words:

```
## <Role name>: round 1

### Findings
**<ROLE-CODE>-1: <short title>**
- Target: decision <N> | gap (not covered by any decision)
- Attack: <what breaks, for whom, under what scenario>
- Severity: blocker | major | minor
- Evidence: <file:line or URL, or "inference">
- Amendment: <concrete, testable change to the plan or an added decision>
- Changes an accepted product decision (1-12): yes/no

(up to 8 findings, most severe first)

### Keep
<1-3 decisions you actively endorse from your specialty, one line each>

### Questions only Prateek can answer
<0-3 product questions, if your findings depend on them>
```
