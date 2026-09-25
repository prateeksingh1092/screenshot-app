# Cursor project workflow

Cursor desktop is the chosen IDE. Codex leads through OpenAI's official extension or Codex CLI in the integrated terminal, authenticated through the existing ChatGPT subscription. Cursor Ultra models and tools may complement Codex using the existing plan's included allowance.

## Local installation

- Desktop: `/Users/16intelmac/Applications/Cursor.app`, version 3.21.18, Intel x86_64.
- Workspace: `/Users/16intelmac/Documents/Claude/Projects/screenshot-app`.
- Codex extension: `openai.chatgpt` version 26.908.40401, installed in Cursor.
- Codex CLI: `/Users/16intelmac/.local/bin/codex`, version 0.156.0; `codex login status` confirms ChatGPT authentication.
- Cursor CLI agent: `/Users/16intelmac/.local/bin/cursor-agent`, installed and authenticated during setup. Use for bounded complementary tasks after checking the included-usage spending boundary.
- Do not use the bare `agent` command without checking it: it currently resolves to Grok.
- Codex CLI and its official IDE extension share cached authentication. If the extension asks for sign-in, choose ChatGPT, never an API key.

## Models and billing

Codex owns planning, integration, and final verification. The project Codex config pins `gpt-6-astra`, `model_reasoning_effort = "high"`, and `forced_login_method = "chatgpt"`; the OpenAI provider is Codex's default and cannot be set project-locally. Project config applies in trusted workspaces; verify the model and ChatGPT account shown by Codex before starting work. Cursor may provide an explicit complementary model for a bounded task; record the model and have Codex assess its result. The user's Cursor Ultra clarification supersedes the earlier Codex-only restriction.

Use only the existing ChatGPT and Cursor Ultra included allowances. Do not buy credits, enable add-ons, use API-key billing, enable on-demand/overage charges, or add subscriptions. If an allowance is exhausted, stop that route and report it. Prateek explicitly verified that Cursor On-demand spending is disabled; the pending account-confirmation blocker is resolved. This is user-verified state, not a dashboard inspection by Codex. Recheck if there is evidence that the account or billing settings changed; do not repeatedly ask for the same confirmation.

Workspace settings open the Codex extension on startup. The temporary restrictions on inline suggestions were removed after the user authorized Cursor's complementary capabilities. AGENTS.md is an operating rule, not an account-wide billing firewall; it cannot disable purchases or credits on the provider's dashboard.

## When to use each environment

| Work | Lead/tool | Reason |
|---|---|---|
| Product decisions, Pocock documents, integration, final verification | Codex | One owner keeps accepted scope and evidence consistent. |
| Editing, navigation, visual diffs, local inspection | Cursor IDE | Keeps the relevant files and changes visible. |
| Independent design critique or bounded code review | Explicit Cursor Ultra model, when useful | A complementary review should challenge a specific decision, not repeat the entire task. |
| Scripted analysis or a supervised background task | Codex CLI; Cursor CLI when complementary | Reproducible prompts, logs, and exit status. |
| Native builds, tests, profiling, permission-dependent capture tests | Apple toolchain and the actual macOS app; full Xcode for Snapzy’s existing workflow | Editor/model selection cannot establish runtime correctness. |

Do not use two agents to mutate the same files concurrently. Give complementary agents explicit ownership, the governing rules, relevant local skills, accepted decisions, a bounded question, and an output path. Codex reviews the result before incorporating it.

## Skills and rules

Cursor reads the root AGENTS.md. Follow its global-rules pointer first. The existing local Matt Pocock 1.2.3 engineering and productivity skills, including relative reference files, were copied into `.cursor/skills/matt-pocock/`. These are ordinary local Markdown skills, with their upstream license and file-hash provenance; no memory plugin was installed.

Use the matching skill from Cursor's skill picker. Research is already underway; product decisions remain in the local tracker. Do not restart setup or overwrite the user's accepted choices.

1. Read `.scratch/screenshot-mvp/decisions.md` and the latest research.
2. Use research for unresolved facts and grilling/domain-modeling for unresolved product choices.
3. Use to-spec after the shared understanding and test boundaries are settled.
4. Use to-tickets to propose vertical slices and dependencies, then publish the approved breakdown to the local Markdown tracker.
5. Use implement with the prescribed TDD and code-review workflow after scope is ready.

The glossary is CONTEXT.md, not an implementation plan. Research recommendations remain provisional until accepted. Keep global agent rules, including the restrictions on secrets, password storage, and legacy memory locations, in force.

## Native development prerequisite

Full Xcode is currently absent; Command Line Tools are selected. Cursor remains the editing environment. A small CLT probe successfully compiled, linked, and ran with AppKit, SwiftUI, ScreenCaptureKit, and Vision; no capture was performed. Snapzy's existing source build and XCTest workflow still requires Xcode tooling. No passing Snapzy build is claimed. See the [completed Cursor review and Codex validation](../research/2026-09-22-xcode-necessity-assessment.md). Xcode MCP and optional editor extensions are not configured yet.

## Current work

Independent stack research recommends the native Swift hybrid; this is not yet a stack ADR. Snapzy's release architecture and signing were inspected, but the source build, capture UX, and original-image persistence adaptation have not passed evaluation. Continue from `docs/research/2026-09-22-stack-independent-assessment.md` and `docs/research/2026-09-22-cursor-and-foundation-evaluation.md`.
