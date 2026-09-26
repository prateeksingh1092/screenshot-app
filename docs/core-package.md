# Frisket package

The root `Package.swift` is a Swift 6.3 package for macOS 26. It builds what
the app runs and what the tests check. How the app links it is in
[app-build.md](app-build.md).

## What is in it

| Target | Kind | What it holds |
|---|---|---|
| `FrisketCore` | static library product | The pure core: lifecycle, renderer, editor model, selection and window picking, History and export policy. `StorageAdapter/` is its only disk code. |
| `FrisketAdapters` | static library product | `Frisket/Adapters/`: the AppKit, ScreenCaptureKit and Vision adapters (decision 80). |
| `FrisketCoreTests` | tests | The core, through its public seams. |
| `FrisketAdapterTests` | tests | The adapters, with no application host. |
| `HistoryCrashHelper` | test executable | Kills itself at each History commit point for the crash tests. It is not in the app. |

GRDB 7.11.1 is the only dependency. It is pinned once, in `Package.swift`, and
the app and the package read the same `Package.resolved`.

The app links both products and compiles none of their files (decision 80). So
the code the tests exercise is the code the app runs.

## Build and test

Run from the repository root:

```sh
scripts/test-core.sh                        # every package test
scripts/test-core.sh --filter CaptureRendererTests
```

`test-core.sh` sets `DEVELOPER_DIR` to Xcode (the Command Line Tools lack Swift
Testing, decision 47) and keeps every cache inside `.build/`. It runs:

```sh
swift test --disable-sandbox --disable-keychain --disable-xctest \
  --cache-path .build/cache --scratch-path .build \
  --config-path .build/config --security-path .build/security
```

All tests use Swift Testing. A test that reproduces an open defect is wrapped
in `knownDefect("Dn")`; `scripts/ci.sh --defects` lists the ones still red.

Module caches store absolute paths. A `.build/` copied from another worktree
fails with module errors. Delete `.build/module-cache`, `.build/clang-cache`,
`.build/x86_64-apple-macosx` (or `arm64-…`) and `.build/DerivedData`, and build
again.

## The fence

The core may not do disk I/O or use the network. `Checks/check_repository.py`
enforces this and the other invariants (decision 85). `scripts/ci.sh` runs it:

```sh
/usr/bin/python3 -B Checks/check_repository.py --self-test
/usr/bin/python3 -B Checks/check_repository.py --root .
/usr/bin/python3 -B Checks/check_repository.py --root . --check core-io
```

| Check | What it enforces |
|---|---|
| `finalization` | Only `CaptureLifecycleCoordinator` builds an `AuthorizedFinalization`. |
| `app-writes` | The app (`Frisket/`) has no file-write route. Storage writes go through finalization. |
| `storage-pixels` | `StorageAdapter/` never takes a `CaptureImage`, a pixel source or an original. |
| `core-io` | The core imports only Foundation, Synchronization, CoreGraphics, CoreText, ImageIO and Accelerate. `StorageAdapter/` may also import GRDB and Darwin. Outside `StorageAdapter/`, the core names no file route. |
| `input-monitoring` | No event taps and no global event monitors. |
| `network` | No network modules or APIs. |
| `app-sources` | The app compiles no adapter file and links `FrisketAdapters`. |

`--self-test` fails unless every check has a passing and a failing fixture in
`Checks/Fixtures/`. The checks are lexical. They mask comments and strings, but
they can't see an API reached dynamically.

`Checks/check_drift.py` fails when a term in `Checks/retired-terms.tsv` is back
in a live file.

The rest is covered by tests, not by the fence. The clipboard flags are checked
at the adapter (`copyWritesPNGAndConcealedMarkerWithCurrentHostOnly`). Solid
redaction is checked by the renderer tests and the adapter canary tests.

## Capture lifecycle

`CaptureLifecycleCoordinator` is a public actor and the one action interface
(decision 71). The app builds one. Tests build one per case with stand-ins.
`execute(_:) async -> CaptureCommandOutcome` runs every command:

- **Capture:** `capture` (area), `captureFullScreen` and `captureWindow`. Each
  reserves its byte allowance before it asks the source for pixels. The
  permission gate runs first.
- **Deliver:** `copy`, `save`, `drag`, and `retryCopy` and `retrySave` after a
  failed delivery.
- **Leave:** `dismiss`, `exitThumbnail` (timeout, swipe, Close, Esc, overflow)
  and `discard` (Delete).
- **Edit:** `done` renders and finalizes. `render` renders only; a drag from
  the editor uses it and finalizes on an accepted drop.
- **History:** `deleteHistory` and `restoreFromHistory`.
- **Text:** `copyRecognizedText`.

A Pending capture lives in one `PendingCapture` record, in memory (decision
67). Nothing about it reaches disk before an `AuthorizedFinalization`. Copy and
Save commit to History before they write. A drag commits only after the
destination accepts the drop (DA-3).

`thumbnails()` returns each Thumbnail's `status` (`pending` or `finalized`),
whether it is `editable`, and `nextDueAt`. A finalized Thumbnail stays until it
times out or leaves (decision 76). An open editor pauses its Thumbnail's
timeout. The default stack holds 4 Thumbnails and times out after 10 seconds.

`handleSystemEvent` handles quit, screen lock and unlock, and display changes.
`QuitPlan.steps(for:)` decides how Quit ends (decision 73). `Notice.after`
decides what the user is told after each outcome; a success says nothing,
except Save, which names the file.

## Capture renderer

`CaptureRenderer` is the one pixel path for edits (decisions 64 and 75):

- `flatten(_ capture: Data, edits: DocumentEdits) -> Data` makes the delivered
  PNG. The coordinator calls it for Done and for editor Copy, Save and drag.
- `preview(_ capture: Data, maxEdge: 6016) -> CapturePreview` decodes the
  capture once for the editor. `CapturePreview.render(edits)` paints with the
  same `EditPainter.paint` as `flatten`.

At full size the preview equals the decoded output byte for byte. That is the
Delivered image invariant. When the capture is larger than `maxEdge`, each
preview pixel averages only capture pixels in its own block. Every block that
touches a Solid redaction is exactly that redaction's colour (D23).

Painting order:

1. Crop, snapped outward to output pixels.
2. Solid redactions, snapped outward, written as fill bytes with no blending.
   The colour comes from the palette (decision 82) and is always alpha 255.
3. Blur (vImage box, 3 × 3, six passes) and Magnify (2×, no interpolation).
   Each reads only its own box. The redactions are stamped again after them.
4. Annotations, drawn with CoreGraphics and CoreText (decisions 68, 83 and 84):
   in their ink only, above the redactions; no white plate (decision 100). Labels
   use `HelveticaNeue-Bold`. `ArrowGeometry` and `LabelLayout` compute the
   shapes in the core.

The output PNG keeps only the IHDR, IDAT, sRGB, pHYs and IEND chunks; pHYs is
the capture's density, 72 dpi × its display's scale (ticket 102). The capture
sources encode through the same `CaptureRenderer.capturePNG`. A capture is at
most one display (decision 60). The renderer refuses anything taller than
32,768 px, read from the PNG header.

`RenderTimingTests` holds `flatten`, `preview` and `render` under 250 ms at
800 × 1,000 px in a debug build (decision 70). `scripts/editor-memory-run.sh`
measures the peak memory of a full-display edit (decision 72).

## Editor model

- `DocumentEdits` holds the scale, the crop, the Solid redactions, the Blur and
  Magnify boxes and the annotations.
- `UndoableEdits` registers every change with the window's `UndoManager`, with
  a name such as "Undo Crop" (decision 77).
- `MarkEditor` selects, moves, resizes, deletes and restyles marks, and gives
  each mark its VoiceOver label (decision 81).
- `LabelSession` writes typed text into the edits as it is typed (decision 84).

## Choosing what to capture

- `DisplaySelectionSession` and `SelectionGeometry` hold the area Selection. A
  Selection stays on its Origin display.
- `RegionRequest` turns a Selection or a whole display into a display ID, a
  source rectangle snapped to pixels and an output size (decision 65).
- `CaptureDisplays` finds a display by pointer, ID or window overlap, and is
  the one place that flips coordinates.
- `WindowSelection` joins the window-server list with ScreenCaptureKit's
  windows and filters them, including the Capture exclusion list (decisions
  65 and 69).

## History, export and clipboard

- History storage and the launch sweep are in [history-storage.md](history-storage.md).
  `HistoryList` is the History window's read model.
- `PNGFileExporter` names a Save `Frisket 2026-09-25 at 14.03.07.png`, adding
  ` (2)` on a collision (decision 79). `ExportFolderPolicy` refuses History's
  own folder and unwritable folders, and flags iCloud folders.
- `ImageClipboard` and `TextClipboard` writes are marked concealed and
  current-host-only by the adapter.
- `copyRecognizedText` runs `TextRecognizer` on the current revision. A result
  for an older revision is dropped. The outcome carries only a character count.

## Diagnostics

`DiagnosticSink.record(DiagnosticEvent)` takes only closed enums: no
identifier, pixel, text or path. The app injects the adapters'
`SystemDiagnosticLog`, one `os.Logger` line per event (decision 85). Frisket
writes no log file. Without a sink, events are dropped.

## Tool tests

The package suite also runs the Python tests of `Tools/Performance/`,
`Tools/FirstRun/` and `Tools/Release/`. The performance runbooks are
[37](manual-checks/37-performance-baselines.md) and
[38](manual-checks/38-frisket-performance.md).
