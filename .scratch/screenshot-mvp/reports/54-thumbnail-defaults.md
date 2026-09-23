# Thumbnail working defaults and ticket 13 merge scope

Date: 2026-09-23. Research by the delegated Codex agent using the inherited Codex model and read-only shell/source inspection; no Cursor execution in this research pass. This is a recommendation for the coordinator's assessment, not a new accepted product decision. Only this report was written; no git commands, builds, or tests were run.

## Recommendation

Keep **a maximum of 4 cards and a 10-second auto-dismiss delay** as ticket 13's working defaults. **Do not require Settings backing before ticket 13 merges.** Ticket 14 expressly owns the delay/“never” setting and depends on both ticket 11's Settings shell and ticket 13. Ticket 32 owns pausing auto-dismiss under keyboard or VoiceOver focus. These remain requirements for the finished product, not optional polish. This conclusion concerns the defaults question only; it is not a declaration that ticket 13 has passed review or verification. [Ticket 13:9–13][t13], [ticket 14:3–14][t14], [ticket 32:5–13][t32]

Keep the maximum as an internal policy parameter for now. Neither the cited spec nor ticket 14 requires a user-facing stack-size control. Delay/“never” must become a persisted user setting in ticket 14; an injectable constructor argument alone does not satisfy that requirement. [Spec:56–59,142][spec], [ticket 14:13][t14], [policy:12–18][policy]

## Evidence and interpretation

| Source | What it establishes |
| --- | --- |
| Decisions 4 and 22 | The product needs immediate thumbnail actions; decision 22 concerns appearance latency and resource targets. It supplies no evidence for the number of cards or their lifetime. Neither 4 nor 10 seconds is a measured performance target. [Decisions:10,34][decisions] |
| Decisions 31 and 44 | Pending, unedited captures stay in memory; a crash loses them. Decision 44 explicitly makes timeout and overflow finalize to History. Read together, “until acted on” does not prohibit these defined automatic exits. Choosing a different delay must not change the exit outcome. [Decisions:58,71][decisions] |
| Decision 54 | The coordinator is to apply the best-evidenced option without another numerical choice from Prateek. The current 4/10 values are expressly provisional working defaults, with Settings later, not ratified user-visible policy. [Decisions:109–113][d54] |
| Ticket 13 implementation | `ThumbnailStackPolicy` defaults to 4 and 10 seconds. It schedules every inserted card at `now + autoDismissDelay`; overflow takes precedence over timeout when both are due. The implementer identifies both values as their own choices. [Policy:12–18,41–52][policy], [implementer:1–6][impl] |
| Snapzy clone | `QuickAccessManager` defaults auto-dismiss to enabled and 10 seconds, persists these preferences, and restores the same fallbacks. Its cap is **5**, not 4; adding a card at capacity removes the oldest. Its Settings view provides an auto-close toggle and a delay slider from 3 to 30 seconds. [Manager:63–85,157,215–226,295–306][snap-manager], [Settings:56–59,83–99][snap-settings] |

**Why retain these numbers:** 10 seconds has a directly inspected reference implementation precedent. Four cards preserves the current, explicitly provisional project choice; Snapzy's five-card cap is not evidence that five works better with Frisket's panels or displays. I found no comparative usability or layout measurement in the required sources that justifies changing four to five. Confidence is therefore moderate that 4/10 is a reasonable implementation starting point, but low that either is an ergonomic optimum. This is an inference from the evidence above, not an upstream recommendation or a newly accepted decision.

## Required follow-through

For ticket 14, recommend an explicit `never` policy state (an enum or optional deadline), connected to persisted Settings. The current delay is nonoptional, deadlines are mandatory, and zero schedules expiry at insertion time: **zero cannot mean “never” in the existing implementation**. Test that never rejects timeout at arbitrarily advanced clock times while overflow still finalizes to History under decision 44. “Never” should disable the timeout, not silently remove the stack cap or redefine all dismissal. [Policy:14–17,24–27,41–42,57–62][policy], [decision 44:71][decisions], [ticket 14:13–14][t14]

For ticket 32, implement and verify the separate focus-pause requirement. Do not treat a ten-second delay as sufficient accessibility support by itself. [Spec:59,142][spec], [ticket 32:12–13][t32]

The implementer's request for Prateek to ratify the numbers is superseded by decision 54's no-blocking-picks direction. The coordinator can record its assessed choice through the established decision workflow; this report does not edit that record. [Implementer:38][impl], [decision 54:109–113][d54]

## Verification limits

The tests inspected derive the cap and delay from `ThumbnailStackPolicy` and exercise overflow/timeout boundaries. They establish intended semantics, not the optimality of 4/10. Their execution results are the implementer's reported results, not newly reproduced evidence. Manual stack placement, fifth-card overflow, ten-second timeout, full-screen Spaces, multiple displays, and VoiceOver checks remain listed by the implementer. [Tests:79–102,122–151][tests], [implementer:19–36][impl]

Snapzy evidence is limited to the read-only local clone inspected for this report. An attempted web fetch of the previously source-pinned upstream file failed with a cache miss; no claim is made about today's latest upstream release or released-app behavior. The exact local files and line numbers below are the authority for the defaults reported here.

[spec]: /Users/16intelmac/Documents/Claude/Projects/screenshot-app/.scratch/screenshot-mvp/spec.md:49
[decisions]: /Users/16intelmac/Documents/Claude/Projects/screenshot-app/.scratch/screenshot-mvp/decisions.md:10
[d54]: /Users/16intelmac/Documents/Claude/Projects/screenshot-app/.scratch/screenshot-mvp/decisions.md:109
[t13]: /Users/16intelmac/Documents/Claude/Projects/screenshot-app/.scratch/screenshot-mvp/issues/13-thumbnail-stack-and-delete.md:9
[t14]: /Users/16intelmac/Documents/Claude/Projects/screenshot-app/.scratch/screenshot-mvp/issues/14-thumbnail-system-events-and-auto-dismiss.md:3
[t32]: /Users/16intelmac/Documents/Claude/Projects/screenshot-app/.scratch/screenshot-mvp/issues/32-keyboard-and-voiceover-thumbnails.md:5
[policy]: /Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-13/Sources/FrisketCore/ThumbnailStack.swift:12
[impl]: /Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-13/.scratch/screenshot-mvp/reports/13-implementer.md:1
[tests]: /Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-13/Tests/FrisketCoreTests/ThumbnailStackCommandsTests.swift:79
[snap-manager]: /Users/16intelmac/Documents/Claude/Projects/screenshot-app/.scratch/evaluation/Snapzy/Snapzy/Features/QuickAccess/QuickAccessManager.swift:63
[snap-settings]: /Users/16intelmac/Documents/Claude/Projects/screenshot-app/.scratch/evaluation/Snapzy/Snapzy/Features/Preferences/Components/PreferencesQuickAccessSettingsView.swift:56
