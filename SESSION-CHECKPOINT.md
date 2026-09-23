# screenshot-app — resume checkpoint

Read this first after context compaction or in a new Codex session. The repository files own project state; do not restart setup or broad research.

## Latest update (2026-09-22 23:31 UTC): read this first

- Prateek **approved all thirteen architecture recommendations**; recorded as decisions 13-25 in `.scratch/screenshot-mvp/decisions.md`.
- He then asked for specialist roles, a **red-team process** incorporating mutually agreed decisions, and then continuing the Pocock process. The panel (Codex ARCH + seven Cursor Claude Opus 5.5 High roles) is mid-process. **Resume from `.scratch/red-team/status.md`**: it lists every agent id, what is saved, what is pending (SEC and PLAT round 1; the port-vs-scratch side question), known conflicts, the deduplicated questions for Prateek, and the next steps.
- Prateek asked the panel "Why port anything from Snapzy instead of building from scratch?" All eight roles answered "build fresh, Snapzy as reference". **Prateek approved amending decision 13** accordingly: the stitcher is the only port candidate, gated by a trial that needs his build approval (`docs/adr/0001-build-fresh-snapzy-as-reference.md`). Round 2 done: 57 amendments adopted; Prateek answered 17 questions (decisions 27-43). **Red team closed. Spec published at `.scratch/screenshot-mvp/spec.md`. 40 tickets published in `.scratch/screenshot-mvp/issues/` (decisions 44-45). Next: implementation from the frontier (01 hygiene, 02 core package probe, 03 Xcode install), builds only with Prateek's approval.**
- **App name chosen: Frisket** (decision 26; bundle identifier `io.github.prateeksingh1092.frisket`, `.debug` for development builds).
- Accepted decisions stay authoritative in `decisions.md`; red-team output is not accepted until round-2 consensus or Prateek's answer.

## Earlier update (2026-09-22 23:15 UTC)

- Prateek asked to pivot to **GPT-6 Astra, high effort** (Codex lead) together with **Cursor Claude Opus 5.5 High**. Project `.codex/config.toml` now pins `model_reasoning_effort = "high"`; `model_provider` was removed because Codex ignores it in project-local config. A live check confirmed `gpt-6-astra` at `high` through ChatGPT sign-in.
- Lead Codex session `01a0caf9-735d-7eb3-b0cf-327813108ac2` was resumed (not replaced) with `.scratch/evaluation/codex-adaptation-brief.md`; exit 0. Output: `docs/research/2026-09-22-snapzy-history-adaptation.md` (evidence item 5). Verdict: comprehensible but cross-cutting adaptation; Snapzy unselected.
- Cursor Opus 5.5 High wrote `docs/research/2026-09-22-snapzy-local-only-surface.md` (evidence item 6): no default network path carries capture content; the fork would need its own Sparkle feed/key; the `snapzy://` scheme is on by default and can trigger saved+copied captures. Prateek said Codex review of this report is not needed.
- Snapzy clone remains clean at the release commit. No builds, installs, launches, or captures.
- **Next:** Prateek is answering an architecture grilling round (Q1–Q13: foundation strategy, toolchain, platform floor, in-editor original storage, editor exit semantics, quota accounting, automation surface, image format, later distribution, performance targets, test boundaries, accessibility, diagnostics). Record accepted answers in `.scratch/screenshot-mvp/decisions.md`, then compute the next round. Recommendations are not decisions.

## Previous instruction

Prateek asked **Cursor's native Claude Opus 5.5, high effort, to independently determine whether full Xcode is even needed before installing it**. That review is now **complete and assessed by Codex**. Read `docs/research/2026-09-22-xcode-necessity-assessment.md` first. **No Xcode installation has occurred.**

Verified conclusion: full Xcode is not universally needed for a native macOS app, but Snapzy's existing Xcode project/tests require its tooling. A CLT-built x86_64 probe imported/linked AppKit, SwiftUI, ScreenCaptureKit and Vision and ran successfully without screen capture. Separate probes failed for missing PreviewsMacros and XCTest as predicted. Full GUI/capture/OCR/permissions/Swift Testing behavior remains untested.

The latest user request is to make sure everything is saved because context is nearly full. This checkpoint, prompts, accepted decisions, research, and a result collector are saved locally. The collector preserves the public final response and execution metadata; it deliberately does not persist internal reasoning into the repository.

1. Read the completed Cursor response and Codex assessment; do not rerun that research.
2. Continue bounded foundation evaluation. The signed released Snapzy app can be evaluated without a source build; adopting its existing source build/tests requires an Intel-compatible Xcode or a deliberate build-system port.
3. A fresh CLT/SwiftPM native app remains a possibility, not an approved replacement for the Snapzy evaluation. Source-build and foundation decisions remain open.
4. Continue Pocock specification/testing-boundary confirmation and ticketing when the remaining uncertainty is resolved. Do not prematurely mark Snapzy selected or the application implemented.

## Workspace and git

- Local: `/Users/16intelmac/Documents/Claude/Projects/screenshot-app`.
- Remote: private `https://github.com/prateeksingh1092/screenshot-app`, origin on main.
- No app implementation, commits, or pushes yet. Existing project files are untracked; they are saved to disk.
- `.scratch/evaluation/Snapzy/` is an isolated upstream clone, ignored by the parent `.gitignore`; it is not adopted product code.
- Clone tag `v1.32.3`, detached commit `837fc73d9b55dfde203e9d14aeb8c8fae4f0add7`.
- Earlier independent stack report inspected newer master commit `9f48e0304c1aca8a945667b49e9b988958d26e7c`. Keep release/master evidence distinct.

## User's settled directions

Authoritative details: `.scratch/screenshot-mvp/decisions.md`.

- Personal use first, later distribution possible. Avoid recurring product services.
- V1: area/window/full-screen capture, floating thumbnail with copy/save/drag/edit, configurable shortcuts, annotation, solid redaction, local OCR and scrolling capture.
- Local storage; recording, cloud storage and hosted sharing deferred.
- History **on by default**. Dismissing an unedited thumbnail saves it. Opening editor keeps it pending; Done/Copy/Save finalizes only the flattened result. Unredacted originals only during active editing.
- History retains a configurable **30 days or 1 GB**, whichever limit is reached first; remove oldest app-owned history items and preserve explicitly exported files.
- Evaluate Snapzy before choosing to adapt it; independently evaluate its stack against alternatives. Neither foundation nor full specification has been accepted.
- **Continue from this Codex-enabled chat.** Cursor remains the IDE and complementary tool; moving the conversation into Cursor is unnecessary.
- **Codex leads** planning, delegation, integration, and final verification. Native Cursor complementary model must be **Claude Opus 5.5, high effort** (`claude-opus-5-5-high`). This supersedes earlier Codex-only wording.
- Existing ChatGPT and Cursor Ultra included allowances only. No API-key billing, paid overages, added credits, add-ons, or new subscriptions.
- User explicitly verified Cursor **On-demand spending is disabled**. Do not ask again absent evidence of change.

## Completed Cursor review and monitoring provenance

- Exact brief: `.scratch/evaluation/cursor-xcode-brief.md`.
- Runtime directory: `/private/tmp/screenshot-app-cursor-xcode-review`.
- Runner: `runner.py`; monitor PID 18721; Cursor child PID 18722 (verify liveness; PIDs may become stale).
- Started: 2026-09-22 22:52:50 UTC.
- Cursor runtime init confirmed **Claude Opus 5.5 300K High**; requested alias `claude-opus-5-5-high`.
- Cursor session id: `50845b21-3a1f-4b6b-b95e-3af4d5893c3d`.
- Invocation uses explicit Cursor binary, `--print --mode ask --trust --model claude-opus-5-5-high --workspace <repo> --output-format stream-json`.
- `events.jsonl` includes internal reasoning: do not dump it, quote it, or copy it into project documents. Inspect only event metadata, tool activity, public assistant output, and final result. Completed exit 0 at 22:56:47 UTC, no stderr.
- Saved report: `docs/research/2026-09-22-cursor-xcode-necessity.md`; Codex assessment: `docs/research/2026-09-22-xcode-necessity-assessment.md`. Collector finished; no active Cursor research job remains.
- Prior history review was intentionally stopped to prioritize the user's Xcode question. Its prompt is `.scratch/evaluation/cursor-history-brief.md`, runtime `/private/tmp/screenshot-app-cursor-feasibility`, child PID 17629. Completion exit 143 at 22:52:40 UTC. **No completed history-review findings.**

## Environment and completed setup

- Intel x86_64 Mac, macOS 26.7 build 25G229, 16 GB RAM.
- Active developer directory `/Library/Developer/CommandLineTools`; `xcodebuild -version` fails because full Xcode is absent. This proves that invocation cannot work, not that all native development requires full Xcode.
- Current App Store Xcode 27 requires M1 or newer, verified at Apple's listing. Do not attempt the latest App Store install on this Intel Mac. Xcode 26.6 was being investigated as a possible compatible alternative; none was downloaded or installed.
- Cursor desktop installed at `~/Applications/Cursor.app`, version 3.21.18, Intel. Signature and notarization checks passed; running workspace verified through `cursor --status`.
- Codex extension `openai.chatgpt` 26.908.40401 installed. Codex CLI 0.156.0 at `~/.local/bin/codex`; authentication verified as ChatGPT.
- Project `.codex/config.toml` sets existing `gpt-6-astra`, `model_provider = "openai"`, and `forced_login_method = "chatgpt"`. Model availability in the extension was not independently verified. User had been looking at Cursor's main right sidebar; do not assume its picker is Codex's picker.
- `.vscode/settings.json` opens Codex on startup. Earlier temporary restrictions on Cursor features were removed after the user authorized Ultra capabilities.
- Cursor CLI `~/.local/bin/cursor-agent` version 2026.09.18-9a7762b is authenticated. Bare `agent` resolves to **Grok**, so always use the explicit Cursor path.
- Homebrew `/usr/local/bin/brew` exists; `mas` and `xcodes` were not found. No helper tool installation performed.
- Playwright connector expects absent `/Applications/Google Chrome.app`; no browser installed or billing dashboard changed. User confirmation resolved the spending question.

## Research and evidence already complete

- `docs/research/2026-09-22-screenshot-landscape.md`: CleanShot features, alternatives, architecture candidates.
- `docs/research/github-repositories.md`: metadata for 18 source repositories.
- `docs/research/2026-09-22-grok-independent-report.md`: completed earlier Grok 4.7 high report, preserved as independent output.
- `docs/research/2026-09-22-cross-review.md`: Codex assessed Grok's final result and verified disagreements. That user requirement is fulfilled.
- `docs/research/2026-09-22-stack-independent-assessment.md`: separate source-grounded native-vs-SwiftUI/Tauri/Electron/Qt/persistence comparison. Provisional recommendation native Swift + AppKit/SwiftUI + ScreenCaptureKit + Vision + SQLite/GRDB.
- `docs/research/2026-09-22-cursor-and-foundation-evaluation.md`: setup/binary checks and limits; updated with the narrower Xcode necessity conclusion.
- Key source finding: Snapzy persists original image bytes in editable annotation sidecars (`original.bin`) and clear-history can preserve capture files. Its stack fit does not prove its lifecycle fits the accepted finalized-only history.
- Snapzy v1.32.3 released DMG hash matched GitHub: `0fd1f52d92df0bc8118f08d080ba6bf22047c10faac9a48aa5a174835321dadb`. Actual executable contains x86_64 + arm64; signature and Gatekeeper notarization checks passed. **Not installed or launched.**
- Cursor/Snapzy read-only disk images were unmounted; downloaded DMGs remain in `/private/tmp`.
- No source build, upstream test run, OCR/scrolling workflow demonstration, performance measurement, or persistence adaptation has passed yet.

## Pocock process and project rules

- Follow root AGENTS.md and `/Users/16intelmac/.Codex/AGENTS.md`.
- 25 local Matt Pocock 1.2.3 skills plus references/license/provenance are in `.cursor/skills/matt-pocock/`; copied hashes checked. They are regular Markdown files, not a memory plugin.
- Local tracker is `.scratch/<feature>/spec.md` and `issues/<NN>-<slug>.md`; setup docs under `docs/agents/`.
- CONTEXT.md is the domain glossary, not implementation planning.
- Current phase: research/feasibility. After foundation uncertainty is resolved, confirm shared understanding/test boundaries, use to-spec, then user-reviewed vertical slices with to-tickets, then implement/TDD/code-review.
- No full application spec or implementation tickets yet; do not claim they're approved.
- No passwords/secrets in Markdown, no memory plugin installation, no writes to imported memories, no reading `~/.Codex/projects/*/memory/**` or session tapes, no OpenClaw runtime.

## Verification before this checkpoint

Skill-copy hashes matched; project JSON/TOML parsed; local research links existed; Codex login status confirmed ChatGPT; extension installation verified. Cursor review completed and was assessed. Positive native-framework compile/link/run exited 0; Preview and XCTest probes failed for the specific missing tooling. Logs and sources are saved in `.scratch/evaluation/clt-probe/`. Repeat only if relevant files change.
