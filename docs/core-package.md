# Frisket core package

`Frisket` is a Swift 6.3 package with one static library, `FrisketCore`, and
one test target, `FrisketCoreTests`. It targets macOS 26. There are no external
dependencies, executable targets, or capture behavior yet. SwiftPM's default
build uses the host architecture; no cross-compilation flags are set.

## Build and test commands

Run from the repository root. Decision 46 and the ticket implementation request
authorize these builds. No signing, keychain access, or network is needed. Use the pinned Xcode
26.5 toolchain for tests (decision 47); the library also builds with the CLT.

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
For a single test, append `--filter swiftTestingRunsOnSupportedMacOS` or
`--filter repositorySatisfiesStaticChecks` to the test command.

**Installed CLT result (2026-09-22):** the core builds on x86_64 macOS 26.7,
build 25G229, with Apple Swift 6.3.3 (swiftlang-6.3.3.1.3,
clang-2100.1.1.101). Swift Testing compilation fails with
`error: no such module 'Testing'`. The Swift Testing tests are **Xcode-only
for this installed toolchain**, per ticket 02's explicit fallback. Ticket 04 subsequently runs these with Xcode 26.5; see its
[verification draft](../.scratch/screenshot-mvp/reports/04-implementer.md). There
is no XCTest substitution.
**arm64 not executed.**

## Isolated stitcher trial

`Trials/StitcherTrial/` is a separate scratch package. The root manifest and
Frisket's dependency graph do not reference it. Its reproduction commands,
source revision, dependencies, changes, limitations, and ticket 05 cost notes
are in its [README](../Trials/StitcherTrial/README.md).

## Static-check interface

The test target invokes `Checks/check_repository.py` through `/usr/bin/python3`.
The script uses only the standard library; it is tooling, not an app dependency.
It returns zero on success and a diagnostic plus nonzero exit on failure.
The same checks can run independently while the Swift Testing runner is blocked:

```sh
for check in dependencies imports identity provenance; do
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/python3 \
    Checks/check_repository.py --root . --check "$check" || exit
done
for fixture in Checks/Fixtures/*.json; do
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/python3 \
    Checks/check_repository.py --fixture "$fixture" || exit
done
```

- **Dependencies:** evaluate the real manifest with `swift package
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

The inventory explicitly includes `Trials/StitcherTrial/Package.swift`,
`LICENSE`, `Sources/`, `Tests/`, and `Resources/`. Trial source imports obey the
same AppKit/SwiftUI restrictions; trial tests receive provenance checks and,
like root tests, are not app identity. The same leading-licence exception
applies to trial sources; no trial-wide identity or provenance exclusion exists.
Trial README material and nested `.build/` output are not build inputs. Three
on-disk fixtures first failed before this inventory was added (identity,
imports, and unregistered source/test provenance); unlike scanner-only fixtures,
they exercise file discovery. The generated-cache fixture also verifies that
build output is not attributed as source.

Manifest evaluation uses `xcrun swift`, honoring the caller's `DEVELOPER_DIR`
(and defaulting to pinned Xcode), instead of silently forcing CLT inside tests.
The dependency check remains scoped to the root Frisket manifest; the isolated
trial manifest has no external dependencies and is documented separately.

`docs/ported-files.json` contains three trial-only ports; no Frisket application
code is ported.
When an approved trial ports a file, retain its original header verbatim and
record the retained licence preamble as `licenseHeader`, alongside `path`, `upstreamURL`, `revision`, and
`originalPath`. Retain a full copyright/licence comment (including an SPDX
identifier or licence grant). Add any necessary complete third-party notice
separately. The fixture ledger entries are synthetic examples, not real ports.

The fixture interface compares checker output with independent literal
diagnostics in JSON. Each of the four checks was first exercised with a failing
fixture before its implementation. The Swift Testing target runs both the
repository checks and these fixtures when its module becomes available.

For this trial the upstream files had descriptive banners, not per-file licence
text. The complete upstream BSD licence is prepended, each original banner is
preserved, and `licenseHeader` records both. `originalSHA256` records each
unmodified upstream source as additional evidence.
