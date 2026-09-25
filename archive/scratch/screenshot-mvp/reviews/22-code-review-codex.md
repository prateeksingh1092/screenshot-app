Reviewed `1bc6091...987cf01` — Codex GPT-6 Astra, high.

**Standards:** No actionable findings.

**Spec — P1 (high):** [ScreenCapturePolicy.swift:16](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-22/Frisket/Adapters/ScreenCapturePolicy.swift:16) resolves exclusions against the application snapshot fetched **before interactive selection**. If a listed app launches during selection, it is absent from that snapshot and therefore omitted from the final filter, violating “always left out of every capture.” This is a code-derived finding consistent with [Apple’s filter semantics](https://developer.apple.com/documentation/screencapturekit/sccontentfilter), not a runtime reproduction.

Refresh application identities before capture, handle relevant application changes during capture, and add a regression covering launch during selection. Existing seam tests assert requested bundle IDs but cannot detect this platform-level omission.

Empty defaults, Settings Add/Remove controls, persistence wiring, Frisket self-exclusion, and diagnostics without app identities are present. Manual UI and capture verification remain pending.

Window/scrolling commands are genuinely absent: tickets 21 and 35 exist on separate branches and are not merged into this branch or current `main`. Their exclusion coverage remains an integration requirement.

Test rerun was blocked by SwiftPM’s GRDB dependency resolution. Working tree remains clean.

Findings: Standards **0**; Spec **1**, worst **P1**.

Verdict: fix-then-merge