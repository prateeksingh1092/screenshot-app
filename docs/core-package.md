# Frisket core package

`Frisket` is a Swift 6.3 package with one static library, `FrisketCore`, and
one test target, `FrisketCoreTests`. It targets macOS 26. There are no external
dependencies or executable targets. The core implements the fixture capture-to-Copy
command flow; platform capture, pasteboard, and History adapters are not installed. SwiftPM's default
build uses the host architecture; no cross-compilation flags are set.

## Build and test commands

Run from the repository root. Decision 46 and the ticket implementation request
authorize these builds. Use the pinned Xcode 26.5 toolchain for Swift Testing
(decision 47); the library also builds with the CLT. No signing, keychain
access, network, app launch, real screen capture, or real clipboard is involved.

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
for check in dependencies imports identity provenance diagnostics capture-memory; do
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
  unsupported lockfile formats fail. GRDB is not added by this ticket.
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
