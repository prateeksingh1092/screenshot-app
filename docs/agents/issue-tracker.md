# Issue tracker: Local Markdown

Issues and specs live in `.scratch/`.

## Conventions
- One feature per directory: `.scratch/<feature-slug>/`.
- Spec: `.scratch/<feature-slug>/spec.md`.
- Tickets: `.scratch/<feature-slug>/issues/<NN>-<slug>.md`,
  numbered from 01, one file per ticket.
- Record triage state in a `Status:` line near the top.
  Use the strings in `triage-labels.md`.
- Append discussion under `## Comments`.

## Skill operations
- Publish to the issue tracker: create the appropriate local file.
- Fetch a ticket: read its referenced file.

## Wayfinding operations
- Map: `.scratch/<effort>/map.md`, containing Notes,
  Decisions-so-far, and Fog.
- Child tickets: `.scratch/<effort>/issues/NN-<slug>.md`.
- Record `Type:` as research, prototype, grilling, or task.
- Wayfinding lifecycle uses `Status: claimed` or `Status: resolved`.
- Record dependencies as `Blocked by: NN, NN`.
- A ticket is unblocked when all dependencies are resolved.
- Select the first open, unblocked, unclaimed ticket by number.
- Claim by saving `Status: claimed` before starting work.
- Resolve by appending `## Answer`, setting `Status: resolved`,
  and adding a summary and ticket link to the map's Decisions-so-far.
