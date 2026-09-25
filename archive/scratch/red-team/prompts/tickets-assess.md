You are the lead Codex agent for Frisket (repo: /Users/16intelmac/Documents/Claude/Projects/screenshot-app). Read-only; do not edit files.

Cursor Claude Opus 5.5 drafted a to-tickets breakdown at `.scratch/screenshot-mvp/tickets-draft.md` from `.scratch/screenshot-mvp/spec.md` (accepted decisions in `.scratch/screenshot-mvp/decisions.md` win on conflict). Assess it against the to-tickets skill at `.cursor/skills/matt-pocock/engineering/to-tickets/SKILL.md`.

Check:
1. Each ticket is a vertical tracer-bullet slice, demoable or verifiable alone, sized for one fresh context window. Flag horizontal slices that aren't justified prefactoring.
2. Blocking edges: missing edges, and edges that don't genuinely gate the ticket.
3. Coverage: any spec user story, module duty, or testing decision with no home ticket.
4. Merges or splits you'd recommend.
5. Any conflict with decisions.md.

Reply in under 400 words as a numbered list of concrete changes (ticket number, change, one-line reason), then one line "Verdict: approve | approve-with-changes | rework". No preamble.
