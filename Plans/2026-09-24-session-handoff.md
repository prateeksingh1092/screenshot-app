> **Next session starts here:** run the to-tickets skill on `Plans/dreamy-giggling-barto.md` (phases) plus spec stories 82–101. Then do Phase 0. Make and record all technical decisions yourself (decision 57).

# Session handoff: 2026-09-24 (Claude Code, Opus 5.5)

Read this first after a context reset. The authoritative plan is `Plans/dreamy-giggling-barto.md`. This file records what that plan doesn't: this session's results, the open work queue, and where each artefact lives. Nothing here has been merged to `main`. The user has approved the plan document, but said **not to execute the remediation** until told.

## Artefacts

| What | Where | State |
|---|---|---|
| Remediation plan | `Plans/dreamy-giggling-barto.md` | Written and approved; not executed |
| Architecture report (improve-codebase-architecture) | `Plans/architecture-review-2026-09-24.html` (copy of `$TMPDIR/architecture-review-20260924-212057.html`) | Done |
| Live beta notes and evidence | `.scratch/visual-pass/beta/0-summary.md` and files 1–4; `evidence/` (gitignored PNGs) | Untracked |
| Diagnosis red loops | Branch `diagnose/red-loops`, worktree `/tmp/frisket-diagnose`, commit `4869429` | Throwaway; contains `[DEBUG-d3h]` probes (never merge) |
| Glossary update (domain-modeling) | `CONTEXT.md` on `main` working tree | **Uncommitted**; +33 lines: Capturing/Editing/Lifecycle groups; new terms Selection, Origin display, Loupe, Blur, Magnify, Thumbnail |
| Live harness tools | `/tmp/frisket-beta/` (`pattern`, `drive`, `cardact`, `wheel`, `scan`, `redink`, `px`, `sck`, `cstype`, `hit` + Swift sources) | Temporary; Phase 0 promotes them into `Tools/LiveHarness` |

## Run the diagnosis loops

```sh
cd /tmp/frisket-diagnose
M=/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox --disable-keychain --disable-xctest \
  --cache-path $M/cache --scratch-path .build --config-path $M/config --security-path $M/security --filter Diagnose
./d3loop.sh DIAG_NO_BANDS=1 DIAG_STRICT=1 DIAG_DENSE_ROWS=1 DIAG_TRACE=1   # one variable per run
```

Red results (the rectangle control stays green):
- **D1:** arrow wrong from row 388, text repeated from row 303, blur from row 253, magnify from row 256.
- **D2:** the cursor window (id 4) is picked.
- **D3:** steady run 1121/1130 rows, mid-step 1066/1130, flick 465/970.
- **D7:** the staged PNG stays after a cancelled drag.
- **D18:** the redaction covers columns [1,2] instead of [2,3].
- **D19:** after `recover()`, `finalizedImage` and `delete` return `.unavailable`.

## D3 hypotheses (stitcher)

| # | Hypothesis | Result |
|---|---|---|
| H2 | False sticky header/footer from identical uniform rows (`matchingRun`, up to 1/3 of the viewport), after which `cropStoredBands` trims rows | **Confirmed.** Flick 465→565 and mid-step 1066→1090; first viewport intact |
| H1 | First-zero break in `searchDelta` | Falsified. Several deltas tie at 0; the smallest wins anyway |
| H3 | Column sparsity in `rowDistance` | Falsified |
| H5 | Ambiguous ties: sparse overlap rows plus mean/integer scoring let delta 147 (true 150) score 0, and ties go to the smallest | **Confirmed.** Strict max scoring + every row + no bands: steady 1130/1130 and mid-step 1130/1130, exact (true deltas 150/90/60 found) |
| H6 | Flick on periodic content: the harness page repeats every 400 rows, so delta 40 and delta 440 are identical | **Explains the residual flick result:** 570 rows, all correct, just short. The fix is detection plus a "slow down" / retry prompt (plan Phase 3), not a better matcher |

**Seams.** A correct test seam exists for D1 (codec/renderer), D2 (`WindowSelection`), D3 (`ScrollingCaptureSession.ingest`), D7, D18 and D19. There is **no seam** for the app-layer bugs D4, D5, D9, D10, D11 and D12. That is an architecture finding; see candidates #2 and #7.

## Code review of `16e8e3e..HEAD` (the 10 unreviewed commits)

### Standards

Hard violations:
1. `StripPNGEncoder.swift:149-172` binds zlib and libcompression through `@_silgen_name` to get around the core import fence (`check_repository.py`, `core-package.md`); `-lz -lcompression` is linked in both `Package.swift` and the pbxproj.
2. Decision changes are unrecorded:
   - `3d43926` replaced the decision-48 stitcher and rewrote ADR 0001 in place, with no entry in `decisions.md`.
   - It removed the selection magnifier the spec requires (story 6, line 137). This is **new defect D26**.
   - No tickets exist for this work.
3. No model or effort level is recorded (`implementation-workflow.md`).

Smells:
- speculative generality (Vision fields, `EditorToolRole`, `outputCount`, an empty `discardSelectionPreviews`);
- mysterious names (`.fastGuided` on every append; magic number `0x205`);
- repeated switches in `EditorWindow`;
- duplicated code: annotation red ×3, Return/Esc handling ×2, modifier maps ×2, redaction snapping ×2;
- shotgun surgery (`decodedByteCeiling` added three ways);
- primitive obsession (Carbon masks, string toolbar IDs);
- feature envy (`CaptureSurfaces` setting `ThumbnailModel` flags);
- data clumps in `DocumentRenderer`.

### Spec

Missing:
- the loupe (D26);
- the system-font label seam (`outputCount` dead code; D6, D23);
- the deleted 22 stitcher scenario tests and Vision;
- step 6 of visual ticket 04;
- a stale spec: line 126 (port) and line 153 (licence).

Scope creep:
- the unauthorised stitcher rewrite (decision 48 required real sequences first);
- in-core zlib;
- `6d03410` accepting `.unlisted` in the own-app capture filter (low confidence).

Wrong implementations, by commit:
- D3 → `3d43926`
- D11 → `73be4ce` (a makeKey on every preview; the ticket asked for once)
- D5 → `73be4ce` + `6d03410`
- D9 → `73be4ce`
- D13 and D22 → `2e5baca`
- the `73be4ce` plate ring covers earlier ink (the ticket asked for "whole ring before any ink").

D1 and D20 predate `16e8e3e` but were worsened.

## Architecture candidates (codebase-design vocabulary)

1. **(Top)** One Capture renderer for preview and Finalized capture.
2. Pending capture record exposed as Thumbnail status. It replaces the plan's `OutcomePresenter`/`ThumbnailStackPresenter`.
3. Scrolling assembler, tested through `ingest`. Delete `Stitcher.stitch` rather than restoring the old tests.
4. Drag export commits when the promise is written. Replace the `RecordingDragHandoff` fake.
5. History read model: `HistoryStore.rows()` in one query. Delete the Middle Man `CaptureCommandLayer` and the History pass-throughs.
6. `WindowSelection(rows:)` owns the join and the filter.
7. One Region request for area, full and scrolling capture. It replaces the "ScreenGeometry helper".

Plan corrections from this review:
- no D1 interim second render path;
- drop the `editing`/`delivering` enum states;
- no `EditorSessions`/`CaptureLauncher` split before #2;
- `EditorLeave.command(for:)` has no production caller.

## Design it twice: Capture renderer (4 designs requested)

Constraints given to all four designers:
1. Preview at scale s equals the saved PNG downsampled to s.
2. Solid redaction is exact black everywhere.
3. Integer crop.
4. 32,768 px cap.
5. Deterministic on arm64 and x86_64.
6. No disk I/O in the core.
7. The original stays in memory only.
8. The coordinator can inject a failure.

| Design | Returned | Summary |
|---|---|---|
| A. Minimal | ✅ | `CaptureRenderer.flatten(original, edits) throws -> CaptureImage`, `preview(original, maxEdge) -> CapturePreview`, `CapturePreview.image(edits) -> CGImage`. A one-method port `CaptureFlattening` with 2 adapters (production + test `RejectOnce`/`Loop`). Deletes StripPNGEncoder, AnnotationFont, EditorProxy, BitmapCodec+EditorDocument, PNGBitmapCodec, ThumbnailImage and the public DocumentRenderer API. Peak about 2× output RGBA (~1.35 GB at 5120×32,768); parity is exact only at scale 1 |
| B. Flexible | ✅ | `CaptureRendering` port with `plan(job)` and `render(job, as:)`. `RenderJob{source: PixelSource, edits, target: .original / .fit(maxEdge) / .rows(range, of:), quality: .exact / .display}`, `RenderOutput .bitmap / .encoded(format)`. Tile pipeline with per-effect row footprints, and a pixel-pass cache. `StripPNGEncoder` becomes private. Adds `.emptyCrop` and `.tooTall`. Thin spots: `.rows`, quality and HEIC have no callers yet |
| C. Common caller | ✅ | The most common caller is the editor preview (re-rendered on every edit and undo). An `EditedCapture` value (original + edits) offers a memoised `preview(maxEdge:)` and `png()`, with contract `decode(png()) == preview(maxEdge: .max)`. Downsampling rule: blocks that touch a redaction stay exact black, so concealment wins over parity. The seam is a closure (`CaptureRenderer.standard`, with test closures). Pixel maths are integer-only, which is deterministic. Cost: the editor holds the full decoded original (up to ~671 MB). The design leaves font rendering unclear |
| D. Ports & adapters | ✅ | Only one real seam: coordinator → renderer, as `CaptureFlattening.flatten(Data, edits) throws -> Data`. Adapters are `CaptureRenderer` in production and `ScriptedFlattener` in tests (queued failures, then real rendering; replaces `RejectOnceCodec`/`LoopCodec`). `CaptureRenderer.preview(data, maxEdge: 2048) -> CapturePreview.render(edits) -> CGImage` takes the same edits as Done. The pixel-backend, encoder and text-shaping ports are **rejected** as single-adapter seams. Deletes `DocumentRenderer.swift`, `StripPNGEncoder`, `AnnotationFont`, `EditorProxy`, `PNGBitmapCodec`, and `Bitmap`/`EditorDocument`/`BitmapCodec`; `codec:` becomes `flattener:`. Conflicts: synchronous flatten blocks the coordinator actor (async needs `inProgress` inserted before the await); the 32,768 cap conflicts with `scrollingPixelCap` 57,600 and `EditorMemoryRunTests`, so DA-6 must land with it; arm64 golden hashes need a second runner |

**Comparison.**
- **Depth:** A and D are deepest (one flatten call plus a preview session). B trades depth for breadth that has no callers yet (`.rows`, quality, HEIC), which is speculative generality. C is deep for the editor but puts memo state inside a value type.
- **Locality:** every design concentrates the D1, D18 and D23 geometry in one layout.
- **Seam placement:** all four agree there is exactly one real seam, between the coordinator and the renderer.

**Recommendation: a hybrid, taking from each design.**
- **From D, the interface:**
  - `CaptureFlattening.flatten(Data, edits) throws(RenderFailure) -> Data`;
  - `CaptureRenderer.preview(data, maxEdge:) -> CapturePreview.render(edits)`, taking the same edits as Done;
  - `ScriptedFlattener` for tests.
- **From D, internal choices:** keep annotations last (current tests stay valid, so no product change), and reject the internal ports.
- **From C, the parity contract:** `render(edits)` at maxEdge ≥ output size equals `decode(flatten)`. Below that, blocks touching a redaction stay exact black, so concealment wins.
- **From A:** check `.tooTall` before allocating anything.
- **From B, internals only:** per-effect row footprints and a tile pipeline, kept as the Gate B fallback and never exposed.
- **Rejected:** B's public `RenderJob`/`RenderTarget`/`RenderOutput` surface.
- **Must land with it:** DA-1 (fence) and DA-6 (the 32,768 cap and `scrollingPixelCap`).
- **Font:** CoreText with a pinned font, smoothing off, checked by golden hashes on both architectures.

**Open product question (resolved by the hybrid):** designs A and B stamp redaction last, which would hide annotations drawn inside redaction boxes and change existing tests. The hybrid keeps annotations on top, as today. Confirm with Prateek only if he wants redaction to hide ink.

**Both returned designs flag one product question for Prateek:** the final redaction stamp hides annotations drawn inside a redaction box (the strict reading of constraint 2). The tests `annotationsDrawAboveRedactionsWithoutClearingNeighbourFill` and `AnnotationCanary` would have to change. Also undecided: the coordinator's `codec != nil` branch at `CaptureLifecycleCoordinator.swift:521`.

## Domain modeling (done)

Terms added to `CONTEXT.md`: Selection, Origin display, Loupe, Blur, Magnify, Thumbnail. Solid redaction's avoid-list was widened.

Contradictions between code and glossary to fix later:
1. The editor button says "Keep in History" (`EditorWindow.swift:167`) while the toolbar label and glossary say **Done**.
2. The Thumbnail accessibility title is always "Pending capture" (`ThumbnailPanel.swift:293-294`), including after Done.
3. The staged drag PNG is an untracked file under the History root, which breaks the App-owned file definition.
4. The Loupe is missing (D26).
5. `CaptureSurfaces.swift:258` misuses "redacted result".

ADR offers, contingent on sign-off: DA-1 (CoreGraphics in the core), DA-2 (no system-shortcut takeover), DA-11 (History durability). The stitcher replacement also needs a `decisions.md` entry.

## Work queue (in order, as asked by the user)

1. **Finish design-it-twice.** Collect designs C and D, compare them by depth, locality and seam placement, and make an opinionated recommendation (a likely hybrid: A's small interface plus B's per-effect footprints/tiles kept internal).
2. **`/tdd`**, after design-it-twice: drive the chosen renderer red→green on the throwaway branch (`diagnose/red-loops`) or a fresh `tdd/capture-renderer` branch. The D1 loops are the first red tests. Keep `main` untouched unless the user says otherwise.
3. **DONE: archived into `archive/`** (147 `git mv` renames, staged, not committed; `archive/README.md` maps old paths to new; `.ignore` holds `archive/`; `.gitignore` lamp.jpg path updated; all 8 repository checks pass). Original entry: Proposed list, with no code, test or script references:
   - `.scratch/red-team/`
   - `.scratch/screenshot-mvp/{reports,reviews,demo}/`, `tickets-draft.md`, `first-commit-paths.txt`, `next-session-demo-video.md`
   - `SESSION-CHECKPOINT.md`
   - `docs/research/`, `docs/design/`, `docs/stitcher-trial-history.md`, `docs/agents/cursor-workflow.md`
   - `.scratch/visual-pass/next-session.md`

   Keep: `spec.md`, `decisions.md`, `issues/`, `visual-pass/{map.md,issues,beta}`, `docs/{adr,manual-checks,*.md}`, `docs/ported-files.json` (read by `check_repository.py` provenance), `.cursor/skills`. Update the `.gitignore` whitelist path for the demo `lamp.jpg`. Add an `.ignore` file with `archive/` so ripgrep-based search skips it, plus an `archive/README.md` mapping old paths to new ones.
4. **DONE: project `CLAUDE.md` (43 lines) and `AGENTS.md` (pointer), staged.** Original entry: for this repo only (not the global file). Use the writing-for-agents skill:
   - short, with positive statements of the sources of truth (the plan, `CONTEXT.md`, `decisions.md`, `spec.md`);
   - build/test commands left to the environment (`scripts/test-core.sh`, `docs/app-build.md`);
   - invariants (pending capture in memory; exact-black redaction; core without disk I/O; no network);
   - the working set is everything outside `archive/`.

   `AGENTS.md` becomes a pointer to `CLAUDE.md` so Codex and Cursor read the same rules. The user wrote "abide by the '...fill in ...here'", which looks like an unfilled placeholder. It was interpreted as the remediation plan plus decisions and glossary; **confirm with the user**.
5. **Phase −1 of the plan:** the decisions are recorded (decision 57) and the spec is updated (stories 82–101). **Next: run to-tickets** on the plan phases and stories 82–101 into `.scratch/screenshot-mvp/issues/` (numbering continues from 42). Then Phase 0. Prateek does not choose between technical options: decide with evidence and record the choice (decision 54).

## State left on this Mac

- **Frisket:** still running, unchanged.
- **Clipboard:** restored after both test runs.
- **macOS screenshot shortcuts (7):** still off. The user must re-enable them by hand in System Settings › Keyboard › Keyboard Shortcuts › Screenshots, because Frisket has no record of turning them off.
- **CleanShot:** quit (it had not been running). 12 synthetic test captures in its media folder expire under its 3-day retention. The URL-scheme prompt was declined.
- **Frisket History:** test captures remain; the 4 pre-test captures are untouched. A 744 B test PNG is in `staging/drag`.
- **Test exports:** `~/Pictures/Frisket/Frisket-812101E6-…-r1.png` and `Frisket-29E0BDAC-…-r2.png`.

## Behaviour changes (DONE: added to `.scratch/screenshot-mvp/spec.md` as stories 82–101, with remediation seams under Testing Decisions; stale lines 126 and 153 fixed)

Write the remediation spec to `.scratch/remediation/spec.md`, following the local-tracker convention in `docs/agents/issue-tracker.md`. Test seams, chosen by the coordinator under decision 57:
- `CaptureFlattening.flatten`
- `CaptureRenderer.preview(...).render(edits)`
- `ScrollingCaptureSession.ingest`
- `WindowSelection(rows:)`
- `thumbnails()` Thumbnail status
- `HistoryStore.rows()`
- `deliver(.drag)`

Behaviour changes:
1. The saved, copied and dragged image always matches the editor preview (D1, D23).
2. Labels keep every character exactly as typed, including lowercase and `$ . - %` (D6).
3. Window capture selects the window under the pointer, never the cursor, and failure messages name the real cause (D2).
4. Clicks inside an area or window selection never reach the app underneath, and Esc always cancels. Every selection has an origin display, including when the pointer is on the top pixel row (D4, D14).
5. The editor's Done, Copy and Save are always visible, and ⌘C, ⌘S and Return always work. The finish action is named "Done" everywhere (D5, glossary).
6. Cancelling a drag leaves the capture pending, with nothing on disk; only a drop that a destination accepts finalizes it (D7, DA-3).
7. Copy Text on an image with no text leaves the clipboard untouched and shows a non-modal "No text found" (D8, DA-5).
8. Thumbnails are a fixed size and stack without overlapping (D9).
9. History Delete asks for confirmation. If the capture's Thumbnail is open, it is closed first (D10, DA-4).
10. Scrolling capture:
    - the page keeps keyboard scrolling;
    - pressing ⌘⇧6 again means Done;
    - the stitch is exact;
    - an ambiguous or too-fast scroll prompts "slow down" and keeps the accepted part;
    - output is capped at 32,768 px (D3, D11, D20, DA-6, DA-9).
11. ⌘⇧2 gives keyboard focus to the latest Thumbnail, with a visible focus ring (D12).
12. Frisket no longer changes macOS settings. It shows which macOS screenshot shortcuts to turn off, links to System Settings, and restoring them is opt-in (D13, DA-2).
13. Cropping never leaves a sliver of redacted content visible (D18).
14. History row actions work again after "Try Again" (D19).
15. History items can be restored to a Thumbnail offering Copy, Save, Drag and Copy Text, with no Edit (DA-10).
16. Notices never block; only destructive choices ask (DA-5).
17. The Loupe is back while selecting (D26, spec story 6).
18. History and Settings open on the active display with the right focus. The Thumbnail's accessibility name reflects whether the capture is pending or finalized. Save confirms, and exported file names are dated (D15, D16, D17).

## Live-harness gotchas (for Phase 0, Tools/LiveHarness)

- **Keycodes:** 1–4 are 18–21; **5 is 23 and 6 is 22**. Return is 36, keypad Enter 76, Escape 53, Tab 48, Page Down 121.
- **Retina screenshots:** screen points are screenshot pixels ÷ 2 on the built-in display. A misread once clicked into the terminal.
- **`drive` key guard:** it types only when Frisket or `pattern` is frontmost. Use `cstype` for CleanShot. Carbon hotkeys need CGEvents posted to the HID tap.
- **Pattern tool:**
  - Launch it as `./pattern` and kill it with `pkill -x pattern`; `pkill -f frisket-beta/pattern` misses relative launches.
  - The `--show-scroll` page is not flipped, so it opens at the **bottom**. Scroll to the top first (`./wheel X Y 60 6 40`).
  - Pixel-unit scroll events from `drive` don't move `NSScrollView`; use `wheel`, which sends line units with a nil source.
- **Frisket selection:** it preselects the last selection, so start drags **outside** the hole (click-through, D4).
- **Accessibility vs real clicks:** an AXPress on a Thumbnail's Edit doesn't activate Frisket, and the editor can open behind other windows. A real click does activate it.
- **CleanShot:** its URL API is off by default and shows a consent prompt; decline it and drive CleanShot through its menu with AX. Its overlays are excluded from `screencapture`.
- **Privacy:** crop evidence screenshots to the test windows; the desktop shows personal file names. Save and restore the clipboard around every run.
- **Diagnosis loops:** they need the main repo's `.build/cache` so nothing is fetched from the network. The first build takes about 4 minutes; later ones about 10 seconds. Dense all-column matching in a debug build takes several minutes.

## Working preferences (Prateek)

- He delegates every technical choice (decisions 54 and 57). Decide from evidence, record it, and bring him only product-visible trade-offs, in plain language with a recommendation.
- He values deep, multi-angle analysis and honest verdicts on whether a step is worth doing.
- Stop and report at each phase gate. Save state to files before context runs low. Project instructions belong in this repo's `CLAUDE.md`, not the global one.
- Live UI testing on either screen is fine when he says he's away. Use synthetic content only.
