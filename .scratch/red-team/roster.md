# Red-team panel roster

Started 2026-09-22 ~23:25 UTC at Prateek's request, after he approved decisions 13-25. Every role receives the shared [briefing](briefing.md); role-specific background and focus are recorded here.

| Code | Role | Background given | Model / tool | Agent id |
|---|---|---|---|---|
| ARCH | Principal architect | Full project history (lead session); deep modules, command layer, portability of Snapzy parts, deferred-feature extensibility, cross-decision consistency, sequencing | Codex CLI, GPT-6 Astra high, resumed lead session | `01a0caf9-735d-7eb3-b0cf-327813108ac2` |
| UX | macOS UX/UI and accessibility designer | Apple HIG, menu-bar utilities, floating panels, CleanShot X / Shottr / built-in screenshot patterns; VoiceOver, keyboard access, Reduce Motion, contrast | Cursor, Claude Opus 5.5 High | `2fde8f32-9f18-43df-a854-1a693065d40c` |
| SEC | Security and privacy red-teamer | macOS app security, TCC, pasteboard, APFS/SSD remanence, single-user threat modeling | Cursor, Claude Opus 5.5 High | `d4211874-a435-4259-81fc-bd5364be1a32` |
| PLAT | macOS platform engineer | ScreenCaptureKit, AppKit window levels, Spaces, multi-display/mixed DPI, TCC, global hotkeys, SMAppService, Vision, code-signing identity | Cursor, Claude Opus 5.5 High | `33295a27-4b6b-4656-b007-2414d48a183c` |
| PERF | Performance and reliability engineer | Latency/memory profiling, Intel constraints, image-pipeline costs, file+database crash consistency | Cursor, Claude Opus 5.5 High | `ce8bc2c6-43a6-46ca-b0ba-74f6bf394e1b` |
| QA | Test architect | XCTest / Swift Testing, pixel tests, seams and ports-and-adapters, fixtures, Pocock TDD and to-spec seams | Cursor, Claude Opus 5.5 High | `f16cf29f-b342-4a51-ae52-f28e4c0e15d8` |
| DATA | Data and persistence architect | SQLite/GRDB, WAL, file-row consistency, migrations, quota accounting, portability | Cursor, Claude Opus 5.5 High | `3f6a5555-a98c-47eb-8ad4-466e20029e9d` |
| REL | Release, licensing, distribution engineer | Ad-hoc / Apple Development / Developer ID signing, notarization, BSD-3 compliance, dependency audit, repo hygiene | Cursor, Claude Opus 5.5 High | `b0a2d7aa-d91a-4906-97a3-fb51923a932c` |

## Process

1. **Round 1, independent attack.** Each role attacks decisions 13-25 (and gaps) read-only, returning findings with severity, evidence, and a testable amendment. Saved under `round1/`.
2. **Consolidation.** The facilitator (Cursor Opus 5.5 High, parent session) deduplicates findings into numbered amendments without editorializing.
3. **Round 2, cross-examination.** Every role votes on every amendment: agree, object (with reason and counter-proposal), or abstain (outside role). Saved under `round2/`.
4. **Consensus rule.** An amendment is adopted when at least two roles agree and none objects. An objection with a counter-proposal that the other roles accept replaces the original. Anything still contested goes to Prateek.
5. **Incorporation.** Prateek pre-authorized incorporating mutually agreed decisions. Adopted amendments are recorded in `decisions.md`, with any that change earlier product decisions (1-12) listed explicitly.
