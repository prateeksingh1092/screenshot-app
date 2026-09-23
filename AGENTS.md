## Agent skills

### Issue tracker
Local Markdown specs and tickets live under `.scratch/<feature>/`.
See `docs/agents/issue-tracker.md`.

### Triage labels
Use the five default triage roles as issue statuses.
See `docs/agents/triage-labels.md`.

### Domain docs
Single-context layout: root `CONTEXT.md` and `docs/adr/`.
See `docs/agents/domain.md`.

### Required project workflow
Use the local Matt Pocock skills throughout this project. Research factual
uncertainties with primary sources; resolve product choices through grilling
and domain modeling; then create the local specification and tickets before
implementation. Follow the implementation skill's testing and review process.
Project-local copies of the skills and their referenced templates are under
`.cursor/skills/matt-pocock/` (upstream version 1.2.3; provenance and license
included). Read the applicable SKILL.md rather than reconstructing its process.
Accepted product decisions live in `.scratch/screenshot-mvp/decisions.md`.
Do not promote research recommendations into accepted decisions.

### Cursor IDE
Use Cursor desktop as the project's IDE, per the user's explicit choice.
Use the official OpenAI Codex extension in Cursor or Codex CLI in its terminal
as the lead agent. Cursor Ultra's native agent, models, and other capabilities
may complement Codex when they fit the task better, within the existing plan.
On this Mac, invoke `/Users/16intelmac/.local/bin/cursor-agent` explicitly:
the bare `agent` command currently resolves to Grok. Recheck executable identity
if the environment changes. If Cursor authentication or execution fails,
report the blocker accurately; do not label another agent's output as Cursor's.
Cursor must follow this AGENTS.md and the governing global AGENTS.md.
Read `/Users/16intelmac/.Codex/AGENTS.md` for the global rules on this Mac.
See `docs/agents/cursor-workflow.md` for IDE setup and workflow status.

### Model policy
Codex drives planning, delegation, integration, and final verification.
The user's latest clarification authorizes complementary models and tools
included in their existing Cursor Ultra plan; it supersedes the earlier
Codex-only restriction. Choose an explicit model suited to a bounded task,
record which model/tool produced its result, and have Codex assess the output.
Use Cursor for IDE interaction, focused code exploration, independent reviews,
or other capabilities where it adds value. Do not duplicate work without a
reason or delegate final ownership away from Codex.
For complementary work through native Cursor models, use Claude Opus 5.5
at high effort, as explicitly requested. The verified CLI model identifier is
`claude-opus-5-5-high`; do not silently substitute another model if unavailable.

### Billing policy
Use only the user's existing ChatGPT and Cursor Ultra included allowances.
Authenticate Codex with ChatGPT and Cursor with its existing account; do not
use API-key billing, paid on-demand/overage usage, extra credits, usage-based
add-ons, or new subscriptions. Check that Cursor on-demand billing is disabled
before project inference through Cursor. If included usage is exhausted,
stop that route and report the limit; never activate a paid fallback.
