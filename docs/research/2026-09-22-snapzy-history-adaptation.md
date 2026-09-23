# Snapzy v1.32.3: history and redaction adaptation

Source-only assessment, 2026-09-22. Verified checkout: `837fc73d9b55dfde203e9d14aeb8c8fae4f0add7`; clean before inspection. Every upstream citation below pins this release. The earlier [stack assessment](2026-09-22-stack-independent-assessment.md) inspected master `9f48e030`; its findings are not substituted for release evidence. Codex led this trace with a bounded, read-only persistence research agent. Cursor Opus 5.5 High’s concurrent network/local-only review is separate. No builds, tests, installations, launches, captures, pasteboard operations, or account changes occurred.

**Judgment: comprehensible but cross-cutting adaptation; proportionate effort remains unproven.** This is evidence item 5, not foundation selection. Disabling editable sidecars alone cannot satisfy [accepted decision 5](../../.scratch/screenshot-mvp/decisions.md): capture bytes, history, clipboard representations, asynchronous saves, and derivative files have separate lifetimes.

## One capture’s byte lifecycle

1. **Initial file.** `ScreenCaptureManager.saveImage` encodes captured pixels directly to the chosen file before publishing completion. Auto-save chooses the export directory; otherwise “temporary” means `Application Support/Snapzy/Captures/`, with `temporaryDirectory/Snapzy_Captures/` as fallback. Thus disabling auto-save does not prevent original pixels reaching disk. Scrolling’s merged image joins the same saving path. `PostCaptureActionHandler` optionally copies first, presents Quick Access/editor, then inserts history—even while editing remains active. A configured canvas preset can overwrite the capture and persist its pre-effect original. [Capture:1329–1406][capture], [Temp:40–99][temp], [Scrolling:640–675][scroll], [PostCapture:46–58,319–406][post], [Preset:58–108][preset]

2. **History and thumbnails.** `CaptureHistoryRecord` stores path, timestamps, size, dimensions, type and thumbnail path, not pixels or OCR text. There is no pending/finalized or ownership field. GRDB uses `Application Support/Snapzy/snapzy.db`, with WAL/SHM companions. Quick Access holds an `NSImage` thumbnail in memory; history separately generates JPEGs under `HistoryThumbnails/<UUID>-preview-v2-<capture-time-ms>-<size>.jpg`. After overwriting a capture, `markFileChanged` updates database metadata before deleting cached previews. Those operations are not one transaction. [Record:29–41][record], [Database:56–74,207–235][database], [QuickAccess:259–291][quick], [Thumbnail:328–335,426–450][thumb], [Store:392–420][store]

3. **Editor originals and assets.** `AnnotateManager` loads either its memory session cache or the disk sidecar; closing an editor does not itself clear the cache, which survives until card dismissal. `AnnotationSessionData` includes original bytes, annotations, crop, cutout and embedded assets. With history enabled—or an existing row—committed sessions persist under `AnnotationSessions/<SHA256-normalized-source-path>/`: `original.bin`, optional `cutout.png`, `assets/<UUID>.bin`, and manifest. These retain reversible pixels despite a flattened capture file. Writing uses a hidden staging package, then removes the old package and renames the stage. Size/mtime validation can reject a session without removing its bytes. [Manager:45–85,130–154,279–357][manager], [Session:26–58,213–305][session], [Conversion:105–138][conversion]

4. **Done/Save/Copy.** The renderer composites source and annotations into a bitmap; exporters atomically replace the source file and request history invalidation. However, controller save/close and copy paths mark saved, cache the original-bearing session, and close **before** background disk completion; successful saves then persist that session. Save As writes a separate flattened destination and can create another original-bearing sidecar keyed to it. Quick Access Save moves the source into the export directory, then updates the row and migrates the sidecar: history does not retain a separate owned copy. An opaque filled rectangle can render coverage, but arbitrary fill alpha/corner settings and blur tools are not a validated solid-redaction guarantee. [Controller:591–658,1011–1082,1164–1210][controller], [Exporter:44–113,547–618][exporter], [QuickAccess:1226–1295][quick], [Renderer:54–76][renderer]

5. **Clipboard and drag.** Image copy exposes a file URL plus encoded pixels and TIFF. Rendered editor copy additionally writes `Captures/Snapzy_clipboard_<UUID>.<ext>`; replacing the source cannot retract an earlier copied bitmap. Quick Access drag exposes its existing URL. Editor drag uses a rendered fallback in `Captures/AnnotateDrag/<UUID>/` or writes a file promise into the receiver’s destination; clean sessions can expose the source URL. Fallbacks are prepared before dropping, and successful handoffs can retain them after closing. Pin dragging writes `Captures/PinDrags/`. Earlier partially edited exports therefore require lifecycle tracking too. The editor’s drag preview itself uses `sourceImage`, a separate in-memory exposure. [Clipboard:108–133,207–311][clipboard], [Quick drag:522–546][quickdrag], [Editor drag:63–113,156–241,275–306,343–448][drag], [Pin drag:167–185][pindrag]

6. **OCR text.** Editor OCR processes `effectiveSourceImage`—original or cutout, without annotation compositing—and writes recognized text to the general pasteboard. It can therefore reveal text hidden by visible redaction. The success notifier also submits a preview of up to 200 characters to macOS Notification Center. No history OCR column exists in this release; notification persistence is OS-owned and was not inspected. Retarget OCR to the rendered revision and reject stale results. Disabling success notifications is available configuration. [State:196–205,1833–1889][state], [Notifier:26–45][notifier], [Notification content:27–44][notification]

7. **Dismissal and removal.** Ordinary dismissal preserves an already-recorded temporary capture; clipboard references can preserve otherwise unrecorded files. Startup cleanup also preserves recent unrecorded files while history is enabled, so restart is not immediate sanitization. Retention deletes age/count rows, then unreferenced temporary captures, thumbnails and sessions; external exports survive that sweep. Clear-history deliberately preserves **all capture files**, including app-owned captures. Explicit history deletion instead recycles referenced files—including exports—to Trash; editor deletion similarly trashes its source. Neither row removal nor Trash constitutes byte erasure. [QuickAccess:499–606,1137–1189][quick], [Temp:269–365,452–470][temp], [Retention:63–101,128–201][retention], [History delete:205–227][historydelete], [Editor delete:458–495][editdelete]

This inventory covers screenshot/editor/history representations and local handoffs. Deferred cloud/recording workflows belong to the separate surface review. OS swap, backups and receiver-owned copies are not established by application source inspection.

## Decision 5 classification

Names below are concrete upstream types/files linked above; proposed lifecycle types are not existing features.

| Accepted rule | Classification and required surface |
|---|---|
| History on by default | **Already satisfied.** `CaptureHistoryPreferences` defaults true; `AppCoordinator` registers true. [Preferences:10–20][preferences], [Defaults:42–49][defaults] |
| Dismissing an unedited thumbnail saves it | **Already satisfied as an outcome** when history insertion succeeds. **Code change** to make dismissal the commit boundary: `QuickAccessManager`, `PostCaptureActionHandler`, `CaptureHistoryStore`; handle dismissal/insertion races. |
| Opening editor keeps capture pending | **Code change.** `CaptureViewModel`, `ScreenCaptureManager`, `QuickAccessItem`, `AnnotateManager` and controller need an explicit pending-capture identity/lifetime, rather than assuming a durable source URL. Gate history insertion and automatic exports. |
| Done/Copy/Save finalizes flattened result | **Code change.** Consolidate controller actions, `AnnotateExporter`, clipboard and drag handoffs behind completion-aware finalization; publish success/history only after durable completion. Rendering is reusable. |
| Original only during active editing | **Code change.** Replace committed `AnnotationSessionStore` persistence; release `AnnotationSessionData`, undo/source caches and cutout/assets at finalization. A proposed memory-only pending capture avoids creating an original requiring post-crash cleanup. Update OCR and stale derivative handling too. |
| Configurable 30 days | **Already satisfied** for age-based row retention; default is 30. [Defaults:42–49][defaults] |
| Or 1 GB, whichever first; oldest first | **Code change.** Current second limit is 500 items; it is **configurable off**, not convertible to bytes. Extend `CaptureHistoryRetentionService`, `CaptureHistoryStore`, `CaptureHistoryRecord`, `DatabaseManager` migration, `PreferencesKeys`, settings view and defaults with owned-byte accounting and commit-triggered enforcement. Existing oldest-first ordering is reusable. [Retention:27–101][retention], [Store:475–535][store] |
| Leave explicit exports untouched | **Already satisfied by retention**, but **code change** for consistent ownership across history delete/clear and exports. Separate app-owned history files from export destinations; update `HistoryWindowController`, `TempCaptureManager`, `CaptureStorageManager` and record/schema ownership. Explicit file deletion must remain distinguishable from history removal. |

## Invasiveness and existing tests

The proposed seam is one capture-lifecycle coordinator with pending, committing and finalized states, authoritative flattened pixels, and recoverable owned-file operations. This changes URL-based capture/editor plumbing and several callers, but does not presently require replacing capture frameworks, stitching, rendering or GRDB. It looks **comprehensible**, with moderate-to-high integration risk; merely removing `original.bin` writes would be insufficient. Acceptance remains conditional on the stack report’s Intel/workflow evidence and a bounded implementation experiment.

Retain default-on coverage in `CaptureHistoryPreferencesTests.swift:30–49`. Extend `CaptureHistoryStoreTests.swift:46–111,147–299`, `CaptureHistoryRetentionServiceTests.swift:75–144`, and `HistoryThumbnailGeneratorTests.swift:49–109` for finalization, byte quotas and interrupted cleanup. Replace the persisted-original expectations in `AnnotationSessionStoreTests.swift:40–75`; extend its move/stale/orphan cases at 100–147. These tests currently protect upstream re-editability, not our invariant. [History tests][historytests], [Retention tests][retentiontests], [Thumbnail tests][thumbtests], [Session tests][sessiontests]

Revise `PostCaptureActionHandlerTests.swift:196–218` (early clipboard copy), `QuickAccessHistoryCleanupTests.swift:64–156`, and `QuickAccessClipboardPreservationTests.swift:95–134`. Extend `AnnotateExportSaveTests.swift:49–164` beyond readable-file/dimension checks, plus `AnnotateCoreTests.swift:377–451` and `AnnotateRenderOrderTests.swift:22–78` with opaque-redaction pixel assertions. Add controller-level finalization/restart coverage and rendered-input OCR tests; existing exporter tests explicitly skip interactive pasteboard/save-panel paths. **No tests were run.** [Post tests][posttests], [Cleanup tests][cleanuptests], [Clipboard tests][clipboardtests], [Export tests][exporttests], [Redaction tests][redactiontests], [Order tests][ordertests]

## Forced-quit cases for a later evaluation ticket

Use a synthetic identifiable secret; inspect decoded pixels, assets, text and hidden directories—not only filenames or database rows.

- Kill after initial write/before history insertion, and after editor closes/before render or source replacement. Original capture bytes remain today. Proposed pass: pending captures never publish originals; restart leaves no inactive original.
- Kill after flattened replacement, before DB invalidation, after DB update/before JPEG deletion; race an already-running thumbnail worker. Proposed pass: no stale original preview survives or is recreated.
- Kill sidecar persistence after `original.bin`, after manifest, after old-package deletion/before rename; also interrupt migration before manifest rewrite. Hidden complete stages can satisfy current cleanup validation. Proposed pass: enumerate and remove every original/cutout/asset package, including hidden stages.
- Kill after preparing a pre-redaction drag fallback or copying, before later redaction/finalization; exercise cancelled and successful drags. Proposed pass: app-owned handoff files are revision-bound and never serve stale pixels. Previously delivered external copies remain outside app control.
- Kill retention/delete/clear between row, capture, thumbnail and sidecar removal; inject deletion errors and restart twice. Proposed pass: idempotent recovery preserves exports and retains retry obligations for owned files; no silent successful cleanup.
- Test 30-day expiry and 1-GB overflow independently/together, equal timestamps, oversized captures, shared paths and failing size reads. Count auxiliary owned files consistently; verify deterministic oldest-first removal. Also OCR after redaction and during a revision change must never publish old-source text.

Unresolved evaluation details include crash-safe filesystem/database coordination, large-scroll memory cost, drag-as-finalization and editor-discard semantics, and precise quota accounting. These are not newly accepted decisions.

[capture]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Services/Capture/ScreenCaptureManager.swift#L1329-L1406
[temp]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Services/Capture/TempCaptureManager.swift#L40-L470
[scroll]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Services/Capture/ScrollingCapture/ScrollingCaptureCoordinator.swift#L640-L675
[post]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Services/Capture/PostCaptureActionHandler.swift#L46-L406
[preset]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Services/Capture/ScreenshotPresetAutoApplier.swift#L58-L108
[record]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Services/History/CaptureHistoryRecord.swift#L29-L41
[database]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Services/Cloud/DatabaseManager.swift#L56-L235
[quick]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Features/QuickAccess/QuickAccessManager.swift#L259-L1295
[thumb]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Services/History/HistoryThumbnailGenerator.swift#L328-L450
[store]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Services/History/CaptureHistoryStore.swift#L392-L535
[manager]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Features/Annotate/AnnotateManager.swift#L45-L357
[session]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Features/Annotate/Services/AnnotationSessionStore.swift#L26-L305
[conversion]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Features/Annotate/Models/PersistedAnnotationSessionConversion.swift#L105-L138
[controller]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Features/Annotate/Managers/AnnotateWindowController.swift#L591-L1210
[exporter]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Features/Annotate/Services/AnnotateExporter.swift#L44-L618
[renderer]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Features/Annotate/Services/AnnotateAnnotationRenderer.swift#L54-L76
[clipboard]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Services/Clipboard/ClipboardHelper.swift#L108-L311
[quickdrag]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Features/QuickAccess/Components/QuickAccessDraggableView.swift#L522-L546
[drag]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Features/Annotate/Components/AnnotateDragHandleView.swift#L63-L448
[pindrag]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Features/QuickAccess/Components/QuickAccessPinDragHandleView.swift#L167-L185
[state]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Features/Annotate/AnnotateState.swift#L196-L1889
[notifier]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Features/Capture/OCRResultNotifier.swift#L26-L45
[notification]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Services/Notifications/OCRNotificationContent.swift#L27-L44
[retention]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Services/History/CaptureHistoryRetentionService.swift#L27-L201
[historydelete]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Features/History/HistoryWindowController.swift#L205-L227
[editdelete]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Features/Annotate/Components/AnnotateBottomBarView.swift#L458-L495
[preferences]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/Services/History/CaptureHistoryPreferences.swift#L10-L20
[defaults]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/Snapzy/App/AppCoordinator.swift#L42-L49
[historytests]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/SnapzyTests/Services/History/CaptureHistoryStoreTests.swift#L46-L299
[retentiontests]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/SnapzyTests/Services/History/CaptureHistoryRetentionServiceTests.swift#L75-L144
[thumbtests]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/SnapzyTests/Services/History/HistoryThumbnailGeneratorTests.swift#L49-L109
[sessiontests]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/SnapzyTests/Features/Annotate/AnnotationSessionStoreTests.swift#L40-L147
[posttests]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/SnapzyTests/Services/Capture/PostCaptureActionHandlerTests.swift#L196-L218
[cleanuptests]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/SnapzyTests/Features/QuickAccess/QuickAccessHistoryCleanupTests.swift#L64-L156
[clipboardtests]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/SnapzyTests/Features/QuickAccess/QuickAccessClipboardPreservationTests.swift#L95-L134
[exporttests]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/SnapzyTests/Features/Annotate/AnnotateExportSaveTests.swift#L5-L164
[redactiontests]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/SnapzyTests/Features/Annotate/AnnotateCoreTests.swift#L377-L451
[ordertests]: https://github.com/duongductrong/Snapzy/blob/837fc73d9b55dfde203e9d14aeb8c8fae4f0add7/SnapzyTests/Features/Annotate/AnnotateRenderOrderTests.swift#L22-L78

Verdict: Comprehensible, cross-cutting adaptation; Snapzy remains unselected.  
Change 1: Introduce pending captures and completion-aware flattened finalization.  
Change 2: Eliminate retained originals and stale sidecar, OCR, thumbnail and handoff derivatives.  
Change 3: Add owned-file recovery, byte-based retention and export-safe deletion.  
Uncertainty: Proportional effort and crash correctness require the later bounded experiment.
