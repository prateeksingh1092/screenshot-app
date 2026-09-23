# Red-team status (saved 2026-09-22 23:31 UTC, before context compaction)

Process and roster: [roster.md](roster.md). Shared brief: [briefing.md](briefing.md). Facilitator: Cursor Claude Opus 5.5 High (parent chat). Codex lead session: `01a0caf9-735d-7eb3-b0cf-327813108ac2`.

## Round 1 (independent attack)

| Role | Agent id | Saved |
|---|---|---|
| ARCH (Codex GPT-6 Astra high) | lead session | `round1/arch.md` (Codex `-o`) |
| UX | `2fde8f32-9f18-43df-a854-1a693065d40c` | `round1/ux.md` |
| QA | `f16cf29f-b342-4a51-ae52-f28e4c0e15d8` | `round1/qa.md` |
| DATA | `3f6a5555-a98c-47eb-8ad4-466e20029e9d` | `round1/data.md` |
| REL | `b0a2d7aa-d91a-4906-97a3-fb51923a932c` | `round1/rel.md` |
| PERF | `ce8bc2c6-43a6-46ca-b0ba-74f6bf394e1b` | `round1/perf.md` |
| SEC | `d4211874-a435-4259-81fc-bd5364be1a32` | `round1/sec.md` |
| PLAT | `33295a27-4b6b-4656-b007-2414d48a183c` | `round1/plat.md` |

## Side question from Prateek: "Why port anything from Snapzy instead of building from scratch?"

Prompt: `prompts/port-question.md` (positions B / C-ref / C-clean). Answers go to `port-question/<role>.md`.
- Sent at 23:29 UTC to ARCH (Codex, writes `port-question/arch.md` itself), UX, QA, DATA, REL, PERF (resumed agents; save their responses on completion).
- Sent to SEC and PLAT at 00:01 UTC after their round-1 results were saved.
- **PLAT answered (00:02 UTC): C-ref for all platform code, stitcher exception.** PERF had answered at 23:30 UTC (missed by the facilitator, recovered 00:04): C-ref, porting only the stitcher's alignment scoring, not its frame storage. **SEC answered (00:02 UTC): C-ref, stitcher security-neutral. 8 of 8 complete, unanimous C-ref.** **Prateek approved the amendment to decision 13 (build fresh; stitcher only port candidate, gated by a trial). Recorded in `decisions.md` and `docs/adr/0001-build-fresh-snapzy-as-reference.md`.** Next: round 2 vote on the numbered amendments.

## Round 2 (started 00:09 UTC Sep 23)

Ballot: `prompts/round2-ballot.md` (64 items, conflicts C1 commit protocol, C2 oversized capture, C3 arm64). Sent to all eight: ARCH via `codex exec resume` writing `round2/arch.md` (log `/private/tmp/screenshot-app-redteam/arch-round2.*`); the seven Cursor roles resumed in the background. Save each Cursor response to `round2/<role>.md` with a provenance comment, then tally: adopt when at least two non-author roles agree and none object.

**Round 2 result (00:12 UTC; `round2/tally.md`, script `tally.py`):** all 8 ballots saved. 45 adopted; ARCH-2 and REL-5 superseded; UX-8 lacked two non-author agrees (not adopted); 12 items objected with "lift if" conditions. C1, C2, C3 unanimous (b). New gaps: history database fails to open or migrate (DATA); stitcher trial's XCTest tests vs Command Line Tools (QA).
**Reconciliation (sent 00:13 UTC, `prompts/round2-reconcile.md`):** authors DATA (2,3,4,5), PERF (1,2,3,4,5,7), REL (7), SEC (4) accept or reject each lift condition; save replies to `round2/reconcile-<role>.md`. SEC-6 (backup exclusion) and UX-7 (origin-display confinement) go straight to Prateek.
**Reconciliation result (00:21 UTC):** all 12 accepted with the objectors' conditions folded in (`round2/reconcile-{data,perf,rel,sec}.md`). Totals over 64 items: 57 adopted, 2 superseded (ARCH-2, REL-5), 1 not adopted (UX-8), 2 to Prateek (SEC-6, UX-7). **Done (00:25 UTC):** Prateek answered all 17 questions (decisions 27-43; he overrode C2 by refusing oversized captures from History). Adopted amendments and answers recorded in `decisions.md`; `CONTEXT.md` gained Pending capture, App-owned file, Export, Capture exclusion list. **Red team closed.** Prateek confirmed the three test seams (00:30 UTC). **Spec published: `.scratch/screenshot-mvp/spec.md`, Status ready-for-agent** (81 user stories). To-tickets done: Codex assessed the draft ("rework", 14 changes applied), Prateek approved revision 2 and confirmed the exit outcomes (decision 44). **40 tickets published in `.scratch/screenshot-mvp/issues/`.** Next: implementation per the Pocock implement skill, starting at the frontier (tickets 01, 02, 03), each build needing Prateek's approval.
- **Answers so far (23:32 UTC), 5 of 8, all C-ref:** ARCH (medium; no code proven worth copying; stitcher only after a bounded comparison), QA (medium; stitcher exception with its byte-exact tests), DATA (high; persistence from scratch), UX (medium; all UI from scratch, overlay workarounds become checklist cases), REL (medium; stitcher exception, it is the only identity-clean file). Saved in `port-question/arch.md` and `port-question/panel-answers.md`. Emerging amendment to decision 13: C-ref, with the stitcher as the only port candidate, gated on a bounded extraction spike (compile alone in a scratch package, pass byte-exact tests on this Intel Mac, compare effort to a fresh implementation).
- Facilitator's preliminary reading (not a verdict): round-1 evidence leans toward C-ref (from scratch, Snapzy as read-only reference), possibly porting only the stitcher's alignment computation. If adopted it amends decision 13; flag it to Prateek explicitly.

## Known conflicts for round 2

- **Commit protocol:** PERF-4 wants a `committing` row inserted before the file write, then `finalized`. DATA-2/DATA-3 want the file written, flushed and renamed first, then one row insert; only `finalized` and `deleting` states. Put both as competing amendments.
- **Oversized single capture vs 1 GB:** ARCH-3 flags the contradiction; DATA-4 and PERF-5 propose "eviction stops once only the just-committed item remains". Needs Prateek if not consensus.
- **Universal binary:** QA-5 and REL-6 accept "arm64 built and signed, never executed" labelling, with an Intel-only alternative.

## Convergent themes (likely consensus)

The lifecycle coordinator is a deep module behind the command layer and is the single high test seam (ARCH-1, QA-1). Renderer and stitcher are separate pure seams. Identity by capture UUID under one app-owned root; copy out on export, never move (DATA-1). `F_FULLFSYNC` plus atomic rename plus an idempotent launch sweep (DATA-2, PERF-4). Stitcher rework to strips (PERF-1). Thumbnails from in-memory image (PERF-3). Carbon hotkeys only (PERF-7). Swift Testing for package tests (QA-4). Identity scrub of Snapzy names (REL-1). BSD-3 headers plus provenance manifest if any code is ported (REL-2). Dependency allowlist `{GRDB}` (REL-3). Stable signing identity, never ad-hoc for the installed copy (REL-4, UX-4). Enumerated thumbnail exit paths plus explicit Delete (UX-2). Quit handling for open editors (UX-3). Keyboard/VoiceOver-reachable thumbnail (UX-1). Pre-first-commit repo hygiene (REL-8). Snapzy bugs not to port: debug `eraseDatabaseOnSchemaChange`, and a thumbnail sweep that deletes every current thumbnail.

## Round 1 complete (00:05 UTC, Sep 23): all eight roles saved

SEC and PLAT saved in `round1/sec.md` and `round1/plat.md`; both were then sent the port question (background, pending). Cross-role convergence from them:
- **Self-capture:** PLAT-2 and SEC-2 independently found that `sharingType = .none` doesn't hide windows from ScreenCaptureKit; always exclude our own app with `SCContentFilter`. PLAT-2 also found Snapzy's CoreGraphics capture fast path is obsoleted at the macOS 26 minimum, which further weakens porting its capture code.
- **Stable signing:** PLAT-1 reinforces REL-4 and UX-4.
- **Carbon hotkeys only:** PLAT-4 reinforces PERF-7; adds the ⇧⌘6 Touch Bar collision.
- **Redaction as its own tool:** SEC-1 extends decision 23's opacity test (pixel snapping, `.copy` blend, antialiasing off, sampling effects read the redacted composite).
- New questions for Prateek: auto-scroll with Accessibility vs manual only (PLAT); take over ⇧⌘3/4/5 vs non-conflicting defaults (PLAT); Universal Clipboard and clipboard-manager hiding (SEC); per-app capture exclusion list (SEC); default export folder (SEC). The signing question duplicates item 15.

## Questions only Prateek can answer (deduplicated so far)

1. Oversized single capture: refuse history admission, or keep it with a visible overage? (ARCH, DATA, PERF)
2. Must v1 support re-editing captures reopened from History? (ARCH)
3. Replace macOS Cmd-Shift-3/4/5, or coexist on different defaults? (UX)
4. One-step thumbnail "discard" that bypasses history? (UX)
5. Logout/restart with an unanswered editor prompt: finalize the rendered result, or discard? (UX)
6. Unedited pending thumbnails survive a crash (requires writing to disk before editing)? (PERF)
7. Scrolling capture: stop at about 10 screens at 5K, or auto-switch to 1x? Do you use an external 5K display? (PERF)
8. Is there an external display, ideally 1x, for the multi-display checklist? (QA)
9. "arm64 built but never run" acceptable, or Intel-only until Apple Silicon testing? (QA, REL)
10. Exclude history from Time Machine? (DATA)
11. v1 "move/export all history", or per-item export only? (DATA)
12. Ever persist OCR text for search? (DATA)
13. Product name and bundle identifier (REL). Prateek asked for name recommendations; see below.
14. License for the project's own code; will the repo ever be public? (REL)
15. May a signing identity be created: Xcode Personal Team sign-in, or a self-signed certificate in the login keychain? (REL)

## App name (requested by Prateek at 23:30 UTC; in progress)

Conflict web searches were interrupted before returning; no results yet. Criteria: short, pronounceable, verb-able, macOS-native feel; fits the domain (Capture = still image, Solid redaction, local History); no clash with existing screenshot apps (CleanShot, Shottr, Snapzy, Xnapper, Snagit, Monosnap, Lightshot, Skitch, Capso, Cap, Kap, ScreenFloat, Vellum is a well-known Mac app); bundle identifier `io.github.prateeksingh1092.<name>` (GitHub remote owner), permanent per REL-5, with a `.debug` suffix for development builds. Candidates to vet: Marquee, Stillshot, Scrim, Blackbar, Loupe, Keyline, Opaque, Quietshot. Recommend after conflict checks; the decision is Prateek's.

Conflict checks (web search, 23:40 UTC; not a trademark search):
- Eliminated: Blackbar (paid Mac/Win/Linux app that redacts secrets in screenshots, $19); Marquee ("Marquee – Screenshot Studio", Mac App Store, July 2026); Loupe (Mac App Store screen magnifier that copies pixels); Opaque (opaque.app browser extension blurring text for screen captures; also an App Store Screen Time app); Pinhole (2026 MIT Mac menu-bar overlay utility); Stillframe (App Store frame grabber that runs on macOS 26).
- Survivors, ranked: 1 Stillshot (only a 2012 iPhone video-frame app, apparently inactive); 2 Keyline (Zaikio's active print-shop management app on iPad and web, different category); 3 Quietshot (2026 iPhone silent-shutter camera app, plus a PS Vita plugin); 4 Scrim (Emacs org-protocol utility on the Mac App Store with a `scrim://` scheme; same platform).
- Presented to Prateek; he asked for another round.
- Round 2 (23:50 UTC). Taken: Latent (local-first Mac RAW editor), Tintype (Hipstamatic, Mac App Store), Tacet (haptic metronome, runs on macOS 26), Daguerre (photo-frame app on Mac), Stet (Mac voice-input app), Stillkeep (2026 photo-journal app, runs on Mac). Clear on the Mac: Frisket (only a Rust placeholder crate, a small .NET image tool, a Python data tool), Hushshot (no hits; Hushframe is soundproofing hardware), Keepframe (Unity render sample; a pre-launch mobile photo-culling startup).
- Final shortlist presented: Frisket (recommended), Stillshot, Hushshot, Keepframe. **Prateek chose Frisket (decision 26 in `decisions.md`).** Question 13 above is resolved.

## After the panel

Round 2 (consolidate numbered amendments; every role votes agree/object/abstain; adopt when ≥2 agree and none object; contested items and the questions above go to Prateek). Record adopted amendments in `.scratch/screenshot-mvp/decisions.md`, update `CONTEXT.md` (e.g. Pending capture, App-owned file, Export), write ADR `docs/adr/0001` for the foundation strategy. Then Pocock: to-spec (confirm test seams with Prateek), then to-tickets (quiz Prateek before publishing).
