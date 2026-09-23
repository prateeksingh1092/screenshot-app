# Frisket core package

`Frisket` is a Swift 6.3 package with one static library, `FrisketCore`, and
the core test target `FrisketCoreTests`, plus a test-only `FrisketAdapters`
module and `FrisketAdapterTests` compiling the app adapter sources. It targets macOS 26.
GRDB 7.11.1 is its only external dependency, pinned to the official HTTPS source
and linked statically. `HistoryCrashHelper` is a test-only executable under
`Tests/Helpers/`, built as a dependency of the core tests and absent from the
Xcode project and app bundle. The core implements
capture, Copy, and dismiss-to-History, with app capture and pasteboard adapters.
See the [History contract](history-storage.md) for ticket 09 storage and recovery seams. SwiftPM's default
build uses the host architecture; no cross-compilation flags are set.

## Build and test commands

Run from the repository root. Decision 46 and the ticket implementation request
authorize these builds. Use the pinned Xcode 26.5 toolchain for Swift Testing
(decision 47); the library also builds with the CLT. No signing, keychain
access, app launch, real screen capture, or real clipboard is involved. The first
resolution fetches only the approved GRDB dependency.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"

swift build --disable-sandbox --disable-keychain \
  --cache-path .build/cache --scratch-path .build \
  --config-path .build/config --security-path .build/security

swift test --disable-sandbox --disable-keychain --disable-xctest \
  --cache-path .build/cache --scratch-path .build \
  --config-path .build/config --security-path .build/security
```

The local cache paths avoid writes outside the workspace. `--disable-sandbox`
disables SwiftPM's nested manifest sandbox because the agent sandbox rejects
`sandbox_apply`; it does not disable the agent's filesystem restrictions.
`--disable-keychain` avoids credential lookup, and `--disable-xctest` prevents
SwiftPM from generating an XCTest runner. All authored tests import `Testing`.
For a single test, append `--filter CaptureCommandsTests` or
`--filter repositorySatisfiesStaticChecks` to the test command.

**Installed CLT result (2026-09-22):** the core builds on x86_64 macOS 26.7,
build 25G229, with Apple Swift 6.3.3 (swiftlang-6.3.3.1.3,
clang-2100.1.1.101). Swift Testing compilation fails with
`error: no such module 'Testing'`. The Swift Testing tests are **Xcode-only
for this installed toolchain**, per ticket 02's explicit fallback. Ticket 04
subsequently runs these with Xcode 26.5; see its
[verification draft](../.scratch/screenshot-mvp/reports/04-implementer.md).
Ticket 06 also executes these Swift Testing tests with Xcode 26.5 (17F42),
Swift 6.3.2, on the same x86_64 macOS build. There is no XCTest substitution.
**arm64 not executed.**

## Scrolling capture stitcher

Decision 48 adopted the adapted stitcher in `Sources/FrisketCore/Stitcher/`.
Ticket 34 retired `Trials/StitcherTrial/` and moved all regression tests and
opt-in probes to the core test target. See [stitcher.md](stitcher.md) for the
pure sequence interface, ownership, current commands, limitations and attribution;
[the fixture guide](../Tests/Fixtures/ScrollingCapture/README.md) defines the
recording format. Real-sequence acceptance remains pending authorized recordings.

## Static-check interface

The test target invokes `Checks/check_repository.py` through `/usr/bin/python3`.
The script uses only the standard library; it is tooling, not an app dependency.
It returns zero on success and a diagnostic plus nonzero exit on failure.
The same checks can run independently while the Swift Testing runner is blocked:

```sh
for check in dependencies imports identity provenance diagnostics capture-memory input-monitoring app-sources; do
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/python3 \
    Checks/check_repository.py --root . --check "$check" || exit
done
for fixture in Checks/Fixtures/*.json; do
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/python3 \
    Checks/check_repository.py --fixture "$fixture" || exit
done
```

- **Dependencies:** evaluate the real manifest with the selected toolchain (`DEVELOPER_DIR`) and `swift package
  dump-package` (no resolution or fetch). Only the official HTTPS
  `groue/GRDB.swift` source is allowed, with or without `.git`. Local, registry,
  lookalike, binary, system, plugin, and macro dependency routes are rejected.
  If `Package.resolved` exists, every pin must also be the approved source;
  unsupported lockfile formats fail. Ticket 09 pins GRDB 7.11.1 exactly.
- **App sources:** parse `Frisket.xcodeproj/project.pbxproj` with macOS `plutil`
  and reject explicit Swift file references under `Frisket/`, resolving nested
  project groups and source-root paths. This guards the synchronized-folder
  workflow; the unsigned build verifies actual target membership.
- **Imports:** all Swift files under `Sources/` are core. AppKit and SwiftUI
  imports are forbidden, including attributed, scoped and conditional imports.
  GRDB imports and qualified types are confined to
  `Sources/FrisketCore/StorageAdapter/`. Comments and string examples are masked;
  executable string interpolations are scanned, including raw strings.
  This lexical check does not prove the absence of inferred/re-exported concrete
  types; code review must preserve the adapter's UI-independent interface.
- **Identity:** scan `Package.swift`, `Sources/`, `Frisket/` (the future app),
  and `Resources/`, including file paths and embedded UTF-8/ASCII asset text.
  Only leading copyright/licence comments and narrowly named licence/notice
  files are exempt. A new product root must be added to the inventory. Research,
  ADRs, tickets, third-party development skills, checker fixtures, and test
  examples are engineering material, not app identity. This scope preserves
  the required reference history. Compressed or encoded assets need review.
- **Port attribution:** scan the same inventory plus `Tests/`. A retained
  upstream licence header or `Frisket-Port:` marker requires a ledger entry.
  Each entry must identify an existing file, HTTPS upstream URL, 40-character
  revision, original path, and exact retained licence header. Missing, changed,
  duplicate, or stale entries fail. Entirely unmarked copied code cannot be
  identified mechanically; the port review must register it before acceptance.

The inventory includes root `Package.swift`, `Sources/`, `Frisket/`,
`Resources/` and `Tests/`. The retired trial has no special inventory or
exceptions. On-disk stitcher fixtures verify source identity/import discovery
and source/test provenance discovery. The generated-cache fixture verifies that
root `.build/` output is not attributed as source.

Manifest evaluation uses `xcrun swift`, honoring the caller's `DEVELOPER_DIR`
(and defaulting to pinned Xcode). Only the root Frisket manifest remains.

`docs/ported-files.json` contains the core stitcher and two ported test files.
Their `originalSHA256` values retain upstream evidence; `adaptedSHA256` records
current bytes and is checked for registered entries that declare it. Change
notes describe both the trial adaptations and product adoption. A tampered-hash
fixture fails even when the licence header is unchanged.
When an approved ticket ports a file, retain its original header verbatim and
record the retained licence preamble as `licenseHeader`, alongside `path`, `upstreamURL`, `revision`, and
`originalPath`. Retain a full copyright/licence comment (including an SPDX
identifier or licence grant). Add any necessary complete third-party notice
separately. The fixture ledger entries are synthetic examples, not real ports.

The fixture interface compares checker output with independent literal
diagnostics in JSON. Each of the original four checks was first exercised with a failing
fixture before its implementation. The Swift Testing target runs both the
repository checks and these fixtures with the Xcode toolchain.

Ticket 37 adds `performanceToolingSatisfiesOfflineChecks` to the Swift Testing
suite. It runs the standard-library Python tests in `Tools/Performance/` without
app launches, network or capture. Standalone: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
/usr/bin/python3 -B -m unittest discover -s Tools/Performance -p 'test_*.py'`.
The native probe is built separately by `bash Tools/Performance/build-probe.sh`.
Measurement gates, definitions, commands, and the ticket 38 log interface are in
[the ticket 37 operator runbook](manual-checks/37-performance-baselines.md).

Ticket 38 connects opt-in `FRISKET_CAPTURE_LATENCY=1` app stdout logging to area
and full-screen selection acceptance and thumbnail presentation submission, using
one monotonic nanosecond clock. The numeric JSONL rows feed ticket 37's existing
`app-latency` and `report` commands. See the
[Frisket measurement handoff](manual-checks/38-frisket-performance.md) for exact
endpoints, operator commands, limitations, and the pending comparison table.
Live baselines, low-power GPU confirmation and Prateek's target ratification
remain pending; the 500 ms placeholder is unchanged.

For the stitcher the upstream files had descriptive banners, not per-file licence
text. The complete upstream BSD licence is prepended, each original banner is
preserved, and `licenseHeader` records both. `originalSHA256` records each
unmodified upstream source as additional evidence.

## Ticket 06 command interface

`CaptureCommandLayer.execute(_:) async -> CaptureCommandOutcome` is seam 1.
Construct one layer for the app, injecting `CapturePixelSource`, `ImageClipboard`,
a `pendingByteLimit`, and optionally a `DiagnosticSink`. Copies of the layer
share one actor-isolated Capture lifecycle coordinator; independent layer
instances are independent sessions. There are no public lifecycle mutators or
private-state queries.

- `capture(CaptureID, maximumBytes:)` reserves that allowance across the entire
  coordinator before awaiting the source. The source must respect the allowance
  while producing encoded PNG bytes. Empty and oversized responses are refused;
  failed/refused captures release their reservations and may be attempted again.
  Accepted bytes replace the reservation with their actual byte count.
- `copy(CaptureRevision)` delivers a frozen image. `CopyOutcome` reports the
  revision, `commit`, and `delivery` separately. This ticket always reports
  `notCommitted(historyUnavailable)`; it does not pretend an in-memory result
  was committed to History. Persistence arrives in ticket 09.
- `retryCopy(CaptureRevision)` is available only after a failed delivery and
  uses the retained bytes of that same revision. A repeated Copy returns
  `retryRequired`; a repeated successful delivery returns `alreadyDelivered`.
- `discard(CaptureID)` drops pending or failed-delivery bytes. Discarded IDs
  cannot be reused. Unknown IDs, incorrect revisions, duplicates, and commands
  for an operation awaiting an adapter return typed rejections.

The unedited revision is number 1; editing is outside this ticket. A nonpositive
session budget admits no captures, and a capture allowance must be positive.
Failed and in-flight delivery bytes remain charged; successful delivery and
discard release them. With editing enabled (ticket 26), a successful Copy whose
History commit failed before image writes retains its bytes and receipt for
Edit, Dismiss or Delete; those bytes remain charged. Completed/discarded identifier tombstones remain for the
session, preventing stale commands from creating another capture. This is an
encoded-payload budget, not a bound on the capture adapter's transient decoding
or platform allocations; ticket 08 must enforce its source allowance as well.

`ImageClipboard` exposes only `write(ClipboardImage)` and returns a
`ClipboardReceipt(changeCount:)` or a closed `ClipboardFailure`. Its payload
contains PNG data and immutable `currentHostOnly = true` / `concealed = true`
flags, with no file location, text alternative, or clipboard read method.
An optional `replacing: ClipboardReceipt` restricts a write to an unchanged
change count; the adapter checks this metadata immediately before writing.
The
source adapter owns PNG encoding/validity; the core transports bytes unchanged.
Tests use synthetic byte fixtures, not platform image encoding. The receipt is
recorded in the returned delivery outcome. Honoring pasteboard flags and the
real change count is ticket 08's adapter responsibility.

## Diagnostics and memory-only checks

`DiagnosticSink.record(DiagnosticEvent)` admits only closed event, operation,
error-domain, and error-code enums. The fixed allowed event field is `operation`;
there is no free-form field dictionary, identifier, image, string message, or
underlying platform error. `LocalDiagnosticLog` is actor-isolated and in-memory,
with a clock seam. It expires entries at seven days on both recording and querying;
it does not schedule background work or persist logs. Any later local persistent
adapter must maintain this schema and retention contract. The planted-canary
command test checks exact events and serialized records while proving that the
clipboard receives the synthetic pixel/text/path payload intact.

Two additional lexical checks run with the existing checks and fixtures:

- `diagnostics` rejects direct logging/assertion routes (including raw system
  logging) and additions of non-allowlisted diagnostic payload fields. In this
  core, all diagnostics use the closed event interface; no assertion message or
  system-log string route is used.
- `capture-memory` forbids platform imports and known filesystem capabilities
  in the memory-only core, allowing CoreGraphics/Vision only under `Stitcher/`,
  and checks the image-only, write-only clipboard
  declaration. A future `StorageAdapter/` is the sole disk-capable exception;
  direct references from the lifecycle remain forbidden. Capture and Copy have
  no app-owned root, file store, or filesystem capability in this ticket.

These are conservative lexical guards, not a Swift semantic or capability
proof. New indirect filesystem routes and future platform adapters still need
review. No real root or clipboard is touched by the command tests.

## Ticket 08 app integration

See [app build and signing](app-build.md). The app links a native static target
from the exact core source directory; SwiftPM remains the automated test runner.
`CaptureCommandLayer.image(for:)` exposes revision-bound in-memory bytes for
thumbnail downsampling, returning nil for unknown, stale, released or discarded
revisions. Editable copied captures with a pre-write History failure remain
queryable until resolved. Cancellation is a typed capture-source outcome. Lifecycle and byte
ownership remain in the coordinator.

The app's Xcode build always runs the `input-monitoring` static check. The new
Swift Testing suite exercises selection/pixel stand-ins and the actual AppKit
pasteboard item/options adapter through seam 1. No general pasteboard object,
screen-capture call, permission prompt, or application host is used in tests.

## Ticket 20 full-screen capture

`captureFullScreen(CaptureID, maximumBytes:)` uses the optional `fullScreenSource`
injected into the same command layer. Without that source it reports unavailable;
it never falls back to area capture. Both capture commands share one coordinator,
Pending capture budget and revision-bound Copy, Retry Copy, Dismiss and Delete flow.
With History injected, both finalize through the same commit protocol; the app
shares Dismiss/Escape, Quit, and “Kept in History” feedback for either source.
Diagnostics classify both as the existing closed `capture` operation.

The app's **Capture Full Screen** menu item requests the display under the
pointer, with display-local bounds and native backing-scale pixel dimensions.
The source bounds the raw bitmap before capture. ScreenCaptureKit uses the same
own-app exclusion filter and in-memory PNG encoding as area capture; there is no
window-sharing fallback. Full-screen capture has no hot key in this ticket;
shortcut defaults/remapping belong to ticket 24. Seam 1 fixtures cover 1×, 2×,
negative global coordinates, exclusion requests, Pending image dimensions,
thumbnail downsampling and unchanged Copy bytes. Actual display selection and
OS exclusion require [the manual checklist](manual-checks/20-full-screen-capture.md).

## Ticket 09 verification additions

`sh scripts/test-core.sh --filter HistoryCommandsTests` runs seam 1 with real
files and GRDB/SQLite, synthetic PNGs, a fixed clock, migration fixtures, and
all nine commit-point faults for both area and full-screen captures. The command
uses the same in-worktree caches and
Xcode toolchain as the full `sh scripts/test-core.sh` run. Original ticket 06
History-unavailable descriptions above remain applicable when no `CaptureHistory`
is injected. The app now injects the lazy disk store.

## Ticket 13 thumbnail stack

The coordinator holds a pure `ThumbnailStack` containing exactly its Pending
captures: a card arrives with `.pending` and leaves whenever the capture stops
being pending (a committed exit, Delete, or a successful Copy, Save or Drag). The public interface:

- `ThumbnailStackPolicy(maximumCount: 4, autoDismiss: .after(.seconds(10)))` and a
  `clock: () -> ContinuousClock.Instant`, both optional on the command layer's
  initializer. Decision 54 selects these working defaults; Settings can change
  them later.
- `thumbnails() -> [ThumbnailCard]`: newest first. Each card has its revision,
  `expiresAt` (arrival plus the delay on the injected clock, or nil when
  auto-dismiss is never), optional `displayID`, and `dueExit`:
  `.overflow` beyond the maximum count, otherwise `.timeout` once expired, else nil.
- `execute(.exitThumbnail(revision, exit))`, with `ThumbnailExit.outcome`:

  | Exit | Outcome | Admitted |
  | --- | --- | --- |
  | timeout | finalize to History | only once `expiresAt` is reached |
  | swipe, close, escape | finalize to History | always |
  | overflow | finalize to History | only when the card is beyond the maximum count |
  | delete | discard; nothing written | always |

  An exit that isn't due returns `rejected(thumbnailExitNotDue)` and changes
  nothing. Finalizing exits return `dismiss`'s outcomes, and delete returns
  `discard`'s. After a committed Copy whose delivery failed, delete is still
  `alreadyFinalized` (ticket 09). A failed commit leaves the card on the stack.

Overflow is a separate command rather than a side effect of capture, so the
`capture-memory` rule that capture can't authorize persistence still holds.
The app queries `thumbnails()` after each arrival and removal, and when a card's
`expiresAt` passes, then issues the due exits. Pausing under focus belongs to
ticket 32. Ticket 14 owns quit, display unplug, screen lock, and the
auto-dismiss setting.
`sh scripts/test-core.sh --filter ThumbnailStackCommandsTests` runs the seam 1
tests with a manual clock, real files and SQLite.

## Ticket 14 system events and auto-dismiss

`ThumbnailAutoDismiss.after(Duration)` or `.never`. Zero seconds expire
immediately; never is an explicit flag (`ThumbnailAutoDismissPreference`), not a
zero delay. Overflow still finalizes under never. Settings persist the flag and
seconds separately and call `setThumbnailPolicy`.

`handleSystemEvent`:

| Event | Outcome |
| --- | --- |
| quit | finalize every unedited pending card, oldest first; stop on the first failed commit |
| screenLocked | leave pending and pause timeout; overflow still due |
| screenUnlocked | resume timeout against the original arrival |
| displaysChanged(remaining) | move cards whose display left to `remaining.first`; cards stay pending |

A crash loses unedited pending captures: they exist only in the coordinator's
memory (decision 31). A new command layer on the same History root sees no
pending cards and no History rows. The app observes `didChangeScreenParameters`
and `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`.

## Ticket 15 History window

`historyItems()` is newest first and carries no paths. `historyImage` reads the
finalized PNG. `execute(.copy/.save/.drag)` on a History revision reuses the
delivery adapters, stages a copy for drag, and leaves the owned file. Repeat
Copy is allowed. `deleteHistory` uses the same `deleting` → unlink → row-removed
path as quota eviction; an interrupted delete finishes at the next launch.
Done is `alreadyFinalized`. The History window is a Frisket surface, so capture
already excludes it with the rest of the app.

## Ticket 12 drag handoff

`execute(.drag(revision, operation))` is another exit through the same finalization
policy as Copy and Dismiss. Only `.copy` is accepted; `.move` and `.delete` are
rejected and do not touch History. A copy drag finalizes once, stages the rendered
PNG under `staging/drag/`, and reports commit and delivery separately. The staging
file is deleted only after the promise write completion has returned and the drag
session has ended. `dragStaged` and `dragPromiseWritten` extend `HistoryCommitPoint`.
The app adapter is an `NSFilePromiseProvider` whose dragging mask is `.copy`.
Delivery reports `.copied` only after the destination write, completion callback,
and session lifetime finish. A successful drag removes the thumbnail; a failed
one retains it and suppresses timeout/overflow until an explicit action. Copy,
Save and Drag share the cached History commit, including a failed commit.
The recovery suite covers both drag interruption points in its throw and SIGKILL
tiers, checks that staging survives interruption, then verifies two launch sweeps
preserve History and remove the staging leftovers.

## Ticket 26 editor document, renderer and Done

- **Document:** `EditorDocument(base: Bitmap, edits: DocumentEdits)`. `Bitmap` is
  premultiplied sRGB RGBA8, rows top to bottom. `DocumentEdits` holds `scale`
  (output pixels per document point), an optional `crop` in original document
  points, and the ordered `redactions`.
  `SolidRedaction(x:y:width:height:)` is in document points from the top-left
  and fails for non-finite or non-positive geometry. It has no colour, opacity,
  radius or stroke to set; `SolidRedaction.fill` is opaque black.
- **Renderer (seam 2):** `DocumentRenderer.render(_:) -> Bitmap` is pure Swift
  (Foundation only). Crop is applied first (outward snap to output pixels).
  Each redaction is then shifted into the cropped document, multiplied by
  `scale`, snapped outward, clipped, and copied as fill bytes with no blending
  or antialiasing.
- **Codec seam:** `BitmapCodec` converts PNG bytes to and from `Bitmap` in
  memory. The app injects `PNGBitmapCodec` (ImageIO, fixed sRGB) through
  `CaptureCommandLayer(…, codec:)`; without one, Done returns
  `rejected(.editingUnavailable)`.
- **Done (seam 1):** `execute(.done(revision, edits))` decodes the current
  pending image, renders, encodes, and replaces the pending image with the
  result as revision *n*+1 before any suspension. It then finalizes that
  revision through the same `AuthorizedFinalization` boundary and returns
  `.edited(nextRevision, commit, clipboardFailure:)`. The rendered PNG must fit
  the remaining session byte budget before it can replace the pending image.
  Commit failure leaves the rendered revision
  pending for Dismiss or Copy retries. The original is unreachable either way.
  Every command and `image(for:)` now check the current revision. A committed
  rendered revision stays in memory for the refreshed thumbnail, then Copy
  (reusing the commit) or Dismiss releases it. Done is refused for finalized,
  discarded or recovery-blocked captures (no History re-editing, decision 28).
- **Clipboard:** a copied capture remains editable only if History failed
  before image writes. Done with Solid redactions conditionally replaces that
  capture's earlier copy using its saved receipt, even if History is still
  unavailable. A changed clipboard is untouched. Replacement retains PNG-only,
  concealed and current-host-only delivery. An unavailable clipboard is reported
  separately from the History result, with an explicit Copy action on the
  refreshed thumbnail. Committed copies remain final and cannot be re-edited.
- **Interrupted writes:** History reports `recoveryRequired` once an image
  write has been attempted and finalization fails. Such revisions are frozen
  against further editing because their authorized pixels may already exist
  in staging or recovery files. No recovery or overwrite is attempted here.

Seam 1 canary tests (`EditorRedactionCommandsTests`, adapter test target) use
the real codec, `HistoryStore` and `ThumbnailImage` with 1× and 2× fixtures.
They decode the History image, the History thumbnail cache, the refreshed
on-screen thumbnail and the clipboard stand-in's bytes in fixed sRGB.
The clipboard adapter is exercised with change-count metadata and synthetic
AppKit items; the general pasteboard is never touched by these tests.

## Ticket 23 permission gate

The command initializer now requires a `CapturePermissionSource` in addition to
pixels and clipboard. Existing fixtures explicitly inject a granted stand-in;
the app supplies the CoreGraphics/ScreenCaptureKit adapter. See
[permission model, platform evidence and alert ordering](permission-recovery.md)
and [the manual state checklist](manual-checks/23-permission-states.md).

The app filesystem guard permits the specific recovery forms
`NSWorkspace.shared.open` and `FileHandle.nullDevice`; fixtures still reject
actual file writes in those same files, writable file handles, and POSIX `open`.

## Ticket 18 multi-display selection

`DisplaySelectionSession(displays:pointer:)` is pure layout/selection policy.
`SelectionDisplay` carries the stable display ID, global bottom-left frame,
and backing scale (with the same valid-frame contract as `SelectionGeometry`).
`display(at:)` uses half-open edges; overlapping/mirrored frames choose the
lowest display ID. The invocation display supplies the default keyboard
rectangle. `begin(at:)` chooses and locks the first drag's display;
`update`, `nudge`, and `resize` delegate to the existing `SelectionGeometry`.
`acceptedRect` rejects subpixel/zero-area selections. `updateDisplays` ignores
enumeration order and permanently cancels on added/removed displays or any
frame/scale change, clearing both the rectangle and origin display. A new
session is required after cancellation.

Fixture unit tests cover negative coordinates, shared edges, the origin lock,
reordered layouts, unplugging either display, all displays removed, movement,
scale changes, additions, and rejection of stale selection reuse. A seam-1
pixel/display stand-in drives the same session through an unplug, checking
that no pixels or Pending capture survive, no clipboard write occurs, and a
subsequent selection can use the released budget. The existing hide-before-pixels
and 1×/2× geometry checks continue to apply.

The AppKit adapter presents a nonactivating key-capable panel on every display,
using screen-saver level and `canJoinAllSpaces`, `fullScreenAuxiliary`,
`canJoinAllApplications`, `stationary`, and `ignoresCycle`. Display notifications are observed during selection; Space notifications are
observed from prefetch through capture completion. Space changes re-order all
panels and restore the origin panel's key focus without activating Frisket;
they invalidate frozen previews and end an interrupted drag, retaining the
rectangle. Shareable-content prefetch completes before preview preparation or
selection, preserving permission and pending-alert ordering. Preview sampling
happens before any panel is shown. `AreaCaptureSource` compares
the Space generation across asynchronous prefetch and preparation and discards invalidated
previews before selection. The overlay stamps the accepted rectangle with the
current generation; the source checks it before and after final capture at the
core seam, returning cancellation if it changed. Controlled asynchronous
stand-ins verify preview invalidation, no Pending image after a switch during
final capture, and budget recovery. All panels and
view snapshots are removed before the selection continuation resumes;
`ScreenCapturePlatform` flushes window updates before the final pixel request
and retains own-app exclusion. Layout validation also surrounds asynchronous
preview preparation and final pixel capture. No global event monitors or event
taps are used. OS window ordering, activation, cursor behavior, and actual
pixel output remain [manual checks](manual-checks/18-selection-overlay-displays.md).

## Ticket 11 Save interface

`execute(.save(revision))` and `execute(.retrySave(revision))` return
`.save(SaveOutcome)` with the revision, History `commit`, and file `delivery`
reported separately. Save uses the same shared delivery step and retained commit
result as Copy. Only delivery is retried; successful or failed History commits
are not repeated. Invalid/stale/in-flight commands are rejected before delivery.
Copy and Save have separate retry eligibility. A committed capture cannot be
pending-discarded after export failure; Dismiss retains that single History item.
History failure does not block export and the app presents an acknowledgment
notice when delivery succeeds without History.

The `CaptureExport` adapter accepts only `AuthorizedFinalization`. Its PNG bytes
are the coordinator's frozen output (currently the unedited revision; future
editor rendering must supply its flattened result there). `PNGFileExporter`
creates the selected directory on delivery, writes an exclusively created
temporary file in that folder (mode `0644`, subject to umask), then publishes
the complete PNG with an exclusive rename. It never opens/moves a History
image. `ExportFilenamePolicy` uses
`Frisket-<capture UUID>-r<revision>.png`, followed by `-2`, `-3`, etc. on collisions;
exclusive rename prevents races from overwriting existing files or symlinks.
After 10,000 occupied candidates, delivery reports unavailable. Failed writes
remove only the temporary file created by that attempt. Exports are not registered with
History; retention/deletion operate on app-owned data only.

`ExportFolderPolicy.assess` is pure core policy over path/access/resource facts.
The disk adapter resolves existing ancestors (including symlinks with missing
children), accounts for case-insensitive volumes, and compares volume/file
resource identities on existing ancestors, including roots with missing suffixes.
It refuses this build's History root and the debug and production History roots
under Application Support, including their descendants and aliases, and refuses
unwritable/non-directory destinations. Intermediate symlink replacement between
assessment and writing remains a race; descriptor-relative traversal is deferred.
It checks
again on every delivery, including retries. iCloud detection combines the
`~/Library/Mobile Documents` location with `isUbiquitousItem` on ancestors.
Settings uses the same assessment and warns before accepting an iCloud folder.
No diagnostic carries a filename/path; Save extends the existing closed enums.

The exporter lives in the existing filesystem-capable `StorageAdapter/` and
requires the same finalization capability as History. No static guard exception
was added, and `HistoryStore` recovery internals were not changed.

Focused verification: `sh scripts/test-core.sh --filter
'SaveCommandsTests|ExportFolderPolicyTests'`. Tests use synthetic PNGs, real
SQLite/files in temporary directories, and one held delivery stand-in to test
in-flight command gating. See [manual checks](manual-checks/11-save-and-settings.md)
for the runtime items that remain pending.

## Ticket 10 crash recovery

`sh scripts/test-core.sh --filter HistoryRecoveryTests` exercises the launch
sweep through seam 1 with real SQLite and temporary files. The command uses the
standard `.build` scratch path; tests locate `.build/debug/HistoryCrashHelper`.
Tier 1 throws after every named commit point. Tier 2 launches that helper with
`Process` and requires actual `SIGKILL` termination at every point. Both rebuild
History over the same directory and compare entries, logical sizes and every
file's bytes after two sweeps. Explicit point lists in both tiers are checked
against `HistoryCommitPoint.allCases`; omitting a point must fail the check.

Additional cases cover a separate process holding the root lock, release on
process death, invalid records and undecodable pixel streams, missing images
and thumbnails, interrupted deletions, archive accounting, root relocation,
future migrations with outstanding WAL, symlink refusal and launch ordering.
See [History storage](history-storage.md) for the launch interface and failure
behavior. These tests launch only the helper, never the app, and use synthetic
PNGs and a recording clipboard stand-in.

## Ticket 21 window capture

`captureWindow(CaptureID, maximumBytes:)` uses the optional `windowSource` on
`CaptureCommandLayer`, sharing the permission gate, Pending capture budget,
Copy/Save and their retries, Delete and History finalization with the other
capture commands.
A missing window source fails unavailable without falling back to area capture.
Diagnostics use the existing closed `capture` operation.

`WindowSelection(windows:ownProcessID:ownBundleIdentifier:)` is pure core policy:
its metadata input is front-to-back, in global top-left-origin screen points.
`candidates` excludes off-screen, minimized, own-process,
own-bundle and unidentified-owner windows; `window(at:)` returns the frontmost
eligible hit, preserving negative coordinates and display-spanning bounds.
Visible foreign floating windows remain eligible regardless of window level;
the platform excludes desktop elements.
No titles or pixels enter this policy. The fixture adapter uses this same policy
through seam 1; the live adapter intersects on-screen `SCShareableContent` with
CoreGraphics' metadata-only on-screen z-order. SCK exposes no minimized flag;
minimized windows are absent from this on-screen intersection, and `isActive`
is deliberately not used (Stage Manager can make an off-screen window active).

`WindowScreenCapturePlatform` awaits preparation before lazily showing temporary
nonactivating panels on all displays. Window-local input handles hover, click,
arrows/Tab, Return and Escape. Space/display changes cancel selection. After
hiding and flushing the panels, it reloads the current window list and validates
identity and eligibility. `SCContentFilter(desktopIndependentWindow:)` captures
only the selected foreign window, excluding all Frisket panels by construction;
no display crop or sharing flags are used. Cursor, child windows, shadows and
audio are disabled. Native content dimensions are bounded before requesting
pixels, and encoded PNG bytes are bounded before returning them. Permission
and Space/display generation are checked around asynchronous capture work.

The **Capture Window** menu adds no shortcut (ticket 24 owns that). Runtime
acceptance is pending in [the synthetic-only checklist](manual-checks/21-window-capture.md).
SDK evidence came from installed `SCShareableContent.h`, `SCStream.h` and
`CGWindow.h`; no network research was performed.

## Ticket 35 scrolling capture

`captureScrolling(CaptureID, maximumBytes:)` is seam 1. A `ScrollingFrameFeed`
stand-in supplies manual viewports; there is no synthetic scrolling, event tap,
or global monitor. `ScrollingCaptureSession` keeps the pending original as
LZFSE strips plus the previous viewport, then releases each frame. Done returns
that image through the existing thumbnail, Copy, and History commands. Cancel
releases the reservation and keeps nothing.

`ScrollingCaptureBudget.v1` sets the pixel cap to **294,912,000** (5,120 × 57,600),
the capture ticket 34 completed at a peak physical footprint of **1,270,796,288**
bytes, and the memory budget to **2,000,000,000** bytes, ticket 05's gate.
A command stops earlier when retained strip bytes plus the next frame would
exceed the reserved pending allowance (`maximumBytes`). Pixel cap and memory
budget both stop with `ScrollingCaptureNotice.message` and keep the section
that fit. Starting is refused with `pendingByteBudgetExceeded` when the global
pending-byte budget cannot reserve `maximumBytes`; the feed is not called.

The app menu **Capture Scrolling Page** selects a region with the existing
overlay, then samples that region through `ScreenCapturePolicy` and
`SCScreenshotManager.captureImage`. Live preview, Done, and Cancel are a
nonactivating panel. The automated peak is `sh scripts/scrolling-memory-run.sh`
(opt-in, skipped by the normal suite). Live scrolling on the synthetic page is
[the manual check](manual-checks/35-scrolling-capture.md).

## Ticket 17 History database failure

`historyAvailability()` reports the last open or migration outcome without
creating History or deleting a refused database. Corrupt files, unknown
migrations, and permission failures leave History disabled; capture, Copy,
Save, and drag still deliver. Dismiss stays pending when the commit is
refused. Settings and the History window show a notice, **Try Again**
(`recoverHistory()`), and **Show History Folder**. Recovery never erases the
database; the user can copy it out or repair it, then retry. See
[manual checks](manual-checks/17-history-database-failure.md).

## Ticket 27 crop

`DocumentCrop` is an optional edit in original document points. The renderer
crops first, then snaps redactions outward in the cropped output. Seam 2 tests
cover 1×/2×, fractional rectangles, a frozen snapshot, and render-equivalence
against an independently cropped base. Seam 1 canaries run Done+crop at 1× and
2× and check History, the pending image, both thumbnails, Copy, Save, and drag.
The editor Crop tool (`C`) composes onto an existing crop; the canvas drops the
pre-crop `NSImage` before drawing the new size. See
[manual checks](manual-checks/27-crop.md).
