# Frisket core package

`Frisket` is a Swift 6.3 package with one static library, `FrisketCore`, and
the core test target `FrisketCoreTests`, plus a test-only `FrisketAdapters`
module and `FrisketAdapterTests` compiling the app adapter sources. It targets macOS 26.
GRDB 7.11.1 is its only external dependency, pinned to the official HTTPS source
and linked statically; there are no executable targets. The core implements
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
discard release them. Completed/discarded identifier tombstones remain for the
session, preventing stale commands from creating another capture. This is an
encoded-payload budget, not a bound on the capture adapter's transient decoding
or platform allocations; ticket 08 must enforce its source allowance as well.

`ImageClipboard` exposes only `write(ClipboardImage)` and returns a
`ClipboardReceipt(changeCount:)` or a closed `ClipboardFailure`. Its payload
contains PNG data and immutable `currentHostOnly = true` / `concealed = true`
flags, with no file location, text alternative, or clipboard read method. The
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
thumbnail downsampling, returning nil for unknown, stale, copied or discarded
revisions. Cancellation is a typed capture-source outcome. Lifecycle and byte
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

## Ticket 11 Save interface

`execute(.save(revision))` and `execute(.retrySave(revision))` return
`.save(SaveOutcome)` with the revision, History `commit`, and file `delivery`
reported separately. Save uses the same coordinator branch and retained commit
result as Copy. Only delivery is retried; successful or failed History commits
are not repeated. Invalid/stale/in-flight commands are rejected before delivery.
Copy and Save have separate retry eligibility. A committed capture cannot be
pending-discarded after export failure; Dismiss retains that single History item.
History failure does not block export and the app presents an acknowledgment
notice when delivery succeeds without History.

The `CaptureExport` adapter accepts only `AuthorizedFinalization`. Its PNG bytes
are the coordinator's frozen output (currently the unedited revision; future
editor rendering must supply its flattened result there). `PNGFileExporter`
creates the selected directory on delivery, writes a separate exclusively
created PNG, and never opens/moves a History image. `ExportFilenamePolicy` uses
`Frisket-<capture UUID>-r<revision>.png`, followed by `-2`, `-3`, etc. on collisions;
exclusive creation prevents races from overwriting existing files or symlinks.
After 10,000 occupied candidates, delivery reports unavailable. Failed writes
remove only the file created by that attempt. Exports are not registered with
History; retention/deletion operate on app-owned data only.

`ExportFolderPolicy.assess` is pure core policy over path/access/resource facts.
The disk adapter resolves existing ancestors (including symlinks with missing
children), accounts for case-insensitive volumes, refuses History itself and
its descendants, and refuses unwritable/non-directory destinations. It checks
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
