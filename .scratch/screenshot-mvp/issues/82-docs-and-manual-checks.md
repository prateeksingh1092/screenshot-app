# 82: Docs and manual checks match the product

**What to build:** The build, core-package, stitcher and workflow docs describe the remediated product. The manual checks use ⌘⇧ shortcuts and shrink to what the live harness can't automate.

**Blocked by:** 80, 81

**Phase:** 5

**Status:** ready-for-agent

- [x] `core-package.md` and the build doc are rewritten for the new build graph, fence and renderer.
- [x] The manual checks are updated to ⌘⇧ and cut to what the harness can't automate.
- [x] The plan's §1.4 stale-doc list is empty.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-25: implementer, report

Claude Opus 5.5 (1M context), Claude Code, medium effort (decision 62). Docs only; no code changed and no decision needed.

- **`docs/core-package.md`:** rewritten from its per-ticket log into a description of the package as it is: the two products and the one build graph (decision 80), build and test commands, the fence (decision 85's seven checks and what tests cover instead), the lifecycle seam, the Capture renderer (decisions 64, 68, 70, 72, 75, 82–84), the editor model, window and area picking, History, export, clipboard, OCR and diagnostics.
- **`docs/app-build.md`:** rewritten: configurations, the build graph and the adapter membership-exception rule, `ci.sh`'s five steps, the unsigned build, package resolution, signing, the signed install, what the app stores, and the ⌘⇧ shortcuts under DA-2 (Frisket never writes macOS's shortcuts; the old text still said it turned them off).
- **Stitcher docs:** nothing live was left; `docs/stitcher.md` was deleted by ticket 87.
- **Workflow docs:** `cursor-workflow.md` is in `archive/`. `docs/agents/implementation-workflow.md` gains a note that the implementer brief and decision 62 now govern.
- **Manual checks:** a new `README.md` lists what the harness rows already check, the shared setup and the remaining checks. Every check uses ⌘⇧ and drops what `matrix.tsv` covers. Checks 26–31 are merged into `26-editor.md` (keyboard, VoiceOver, arrow and label looks, close and quit confirmations, editor drag). 33 is folded into 32. 40 is deleted: ticket 40 is closed (decision 60) and ticket 83 replaces it. The Loupe steps are gone (decision 60). 39's case table points at the new steps and marks the harness-covered cases; the record IDs in `Tools/FirstRun/record.py` are unchanged. 38 points at ticket 83 instead of 40.
- **Plan §1.4 stale-doc list, each item:** `stitcher.md`: deleted by ticket 87 (decision 60). `core-package.md:243`: the file is rewritten. `cursor-workflow.md:51` and `SESSION-CHECKPOINT.md`: already in `archive/` (commit a58d918). The ⌃⌥⌘ shortcuts in 9 manual checks: all now ⌘⇧. The list line now says none are left, and the Phase 5 Docs item is marked done.
- **Build caches:** `.build` pointed at ticket-80's paths; the module caches, build products and DerivedData were deleted in this worktree only.
- **Checks:** `check_drift.py` passes; `scripts/ci.sh` prints `ci: green`.
- **Open:** none of the manual checks were run (they need Prateek and the signed app; ticket 83).
