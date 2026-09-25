## Principal Architect: round 1

Read-only review; nothing built, executed, or modified. Release citations below are relative to `.scratch/evaluation/Snapzy/Snapzy/`, pinned to `837fc73d9b55dfde203e9d14aeb8c8fae4f0add7`. Observations support the stated architectural inferences.

### Findings

**ARCH-1: One command layer does not establish lifecycle ownership**

- Target: decisions 17, 19, 20
- Attack: A command dispatcher could merely forward to separate save/copy/drag implementations. Concurrent Copy and Save could finalize twice; a successful history commit followed by failed delivery could misleadingly report total failure and duplicate history on retry.
- Severity: blocker
- Evidence: Observation: `Features/Annotate/Managers/AnnotateWindowController.swift:1011–1047,1164–1210` duplicates finalization orchestration and closes before persistence finishes. Inference: copying that structure behind a dispatcher preserves the problem.
- Amendment: Make the capture-lifecycle coordinator a **deep module** owning transitions and revision identity. Its interface returns separate commit and delivery outcomes; retries reference the same finalized revision. UI adapters depend on this interface; the lifecycle implementation never depends on controllers. Demonstrate duplicate-command, stale-revision, and delivery-retry behavior through that interface.
- Changes an accepted product decision (1-12): no

**ARCH-2: The four proposed ports have different extraction costs**

- Target: decision 13
- Attack: Treating “stitcher, renderer, overlay, database layer” as equally portable can recreate a fork through transitive dependencies.
- Severity: major
- Evidence: Observations: `Services/Capture/ScrollingCapture/ScrollingCaptureStitcher.swift:372–405` accepts `CGImage` and returns stitch outcomes: the strongest extraction candidate. `Features/Annotate/Services/AnnotateAnnotationRenderer.swift:13–37` takes drawing context and image providers, but requires annotation types and optional preview caches. `AnnotateExporter.swift:45–106` additionally owns file writes and history updates. `Services/Capture/AreaSelectionWindow.swift:574,1351` directly controls Quick Access. `Services/Cloud/DatabaseManager.swift:175–235` includes cloud schema and debug schema erasure.
- Amendment: Define four extraction manifests listing retained files, transitive dependencies, replacement interfaces, and excluded behavior. Port stitch computation; extract drawing independently of exporter/controller persistence; return selections from the overlay instead of controlling Quick Access; reuse GRDB techniques, not upstream migrations wholesale. Each extraction must compile without importing upstream application orchestration.
- Changes an accepted product decision (1-12): no

**ARCH-3: The newest-item exception contradicts the retention ceiling**

- Target: decisions 5, 18
- Attack: A finalized PNG plus database overhead can exceed the configured quota by itself. “Enforce 1 GB” and “never evict the just-committed item” cannot both hold without an admission rule or explicit exception.
- Severity: major
- Evidence: Observation: `.scratch/screenshot-mvp/decisions.md:11,29` states both requirements. The oversized-item contradiction is a logical inference, independent of implementation.
- Amendment: Specify either pre-commit admission failure with recoverable export options, or an explicit newest-item overage exception. If choosing the exception, amend decision 5 rather than silently weakening it. Require an oversized-single-capture acceptance case. Accounting implementation is outside my role.
- Changes an accepted product decision (1-12): yes, if the ceiling becomes a target with exceptions

**ARCH-4: Editing an existing Finalized capture lacks defined semantics**

- Target: decisions 5, 16, 17, 20
- Attack: If History can reopen a Finalized capture for editing, its pre-edit pixels already exist on disk. The new memory-only-original rule cannot describe that transition literally. Delete capture also becomes ambiguous: delete the pending revision, the existing history item, or both?
- Severity: major
- Evidence: Observation: `CONTEXT.md:22–27` defines Finalized capture and History, but no revision relationship. Upstream `Features/Annotate/AnnotateManager.swift:130–134` restores editable sessions, which the approved architecture intentionally excludes. The new behavior is unspecified.
- Amendment: Explicitly exclude history re-editing from v1, or define immutable finalized revisions and a separate pending edit. Specify replacement-versus-new-item and deletion semantics, then test history→edit→cancel/finalize/delete transitions through the lifecycle interface.
- Changes an accepted product decision (1-12): no; resolves an unspecified workflow

**ARCH-5: Foundation approval and evaluation gates now disagree**

- Target: decisions 6, 13, 14, 15, 22
- Attack: Implementers may either repeat foundation selection indefinitely or interpret approval of selective porting as evidence that the ports work.
- Severity: major
- Evidence: Observation: `.scratch/screenshot-mvp/decisions.md:24` approves the strategy, while `:42,54` still says foundation selection is pending. `docs/research/2026-09-22-xcode-necessity-assessment.md:22–25,37,43` records only a narrow compiler probe and an unconfirmed installer candidate.
- Amendment: Record strategy selected, individual ports unvalidated. Sequence: confirm compatible installer before installation; establish extraction fixtures independently; measure signed-release baselines without waiting for its source build; require toolchain-backed builds and permission-dependent checks before integrated acceptance. Set measured targets before performance acceptance. Distinguish universal compilation from arm64 runtime verification.
- Changes an accepted product decision (1-12): no; preserves decision 6’s empirical gate

**ARCH-6: “Core Swift package” needs an explicit dependency contract**

- Target: decisions 14, 23
- Attack: Putting upstream files into a package does not prevent application dependencies, preview macros, or Xcode-dependent test infrastructure from following them.
- Severity: major
- Evidence: Observations: `Features/Annotate/Models/AnnotateRenderSnapshot.swift:16–44` references editor-specific types and deferred mockup state. The Xcode assessment at `:23–25` records missing preview tooling and XCTest in the installed CLT.
- Amendment: Define target membership and allowed dependency direction before porting. Keep lifecycle policy independent of AppKit controllers, preferences singletons, and GRDB concrete types; isolate macOS image processing and persistence implementations. Acceptance must separately demonstrate CLT package compilation and the approved Xcode test lane. Do not promise CLT test execution without verifying it.
- Changes an accepted product decision (1-12): no

**ARCH-7: Deferred extensibility can become premature framework work**

- Target: decisions 2, 3, 19, 21
- Attack: A generic media engine, cloud provider registry, or updater abstraction adds concepts without current callers. Conversely, exposing windows or mutable editor state through commands would make future App Intents depend on UI execution.
- Severity: minor
- Evidence: Observation: `CONTEXT.md:7–9` explicitly distinguishes Capture from Recording; decisions defer recording/cloud. Inference: their lifecycle requirements should not be invented now.
- Amendment: Use typed capture IDs, explicit command inputs, and UI-independent results today. Future App Intents call that interface; future cloud receives only finalized artifacts. Keep recording separate until specified. Retain an update ownership note, not an updater implementation. Review imports to verify no deferred feature is required by v1 modules.
- Changes an accepted product decision (1-12): no

### Keep

Decision 13: selective reuse avoids inheriting upstream lifecycle policy wholesale.  
Decision 16: memory-only pending originals establishes a clear lifecycle constraint.  
Decision 19: one command interface can serve current UI and future automation.

### Questions only Prateek can answer

1. For one capture exceeding the quota, prefer refusing history admission or allowing a visible newest-item overage?
2. Must v1 support editing captures reopened from History, or only editing newly captured pending images?