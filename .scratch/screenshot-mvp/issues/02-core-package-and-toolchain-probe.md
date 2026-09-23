# 02: Core package skeleton and toolchain probe

**What to build:** a Swift package for Frisket's core logic that builds and tests without Xcode, proving `swift test` with Swift Testing works under the installed Command Line Tools, plus the static checks every later ticket relies on.

**Blocked by:** None (can start immediately)

**Status:** in-progress (branch `ticket/02-core-package`)

- [ ] The package targets macOS 26 and builds for the native architecture only.
- [ ] One Swift Testing test runs green under `swift test` with the Command Line Tools; if it can't, the blocker is reported accurately and the test is marked Xcode-only.
- [ ] Static check: the only allowed dependency is GRDB (no networking, analytics, updater, or image-format libraries).
- [ ] Static check: core modules never import AppKit, SwiftUI, or concrete GRDB types outside the storage adapter.
- [ ] Static check: Snapzy's name or author appears nowhere outside licence headers and notices.
- [ ] Static check: every ported file keeps its licence header and has a provenance entry.
- [ ] The verification report states the architecture and OS it ran on and that arm64 was not executed.
- [ ] Running the build needs Prateek's approval at the time.

## Comments


### 2026-09-22 — Codex implementation and verification

Resolved using the ticket's explicit CLT-unavailable alternative for the Swift
Testing probe. **No Swift Testing test ran green:** the installed CLT reports
`error: no such module 'Testing'`. Both test files and the package guide mark
these tests **Xcode-only for this toolchain**; execution under Xcode remains
unverified. No XCTest fallback was introduced.

- Architecture: **x86_64** (`uname -m`), confirmed by `file` on the built
  `FrisketCore.swift.o`: `Mach-O 64-bit object x86_64`.
- OS: **macOS 26.7, build 25G229** (`sw_vers`).
- Toolchain: **Apple Swift 6.3.3**, swift-driver **1.148.6**,
  `swiftlang-6.3.3.1.3`, `clang-2100.1.1.101`; target
  `x86_64-apple-macosx26.0`. All Swift commands used
  `DEVELOPER_DIR=/Library/Developer/CommandLineTools`.
- **arm64 not executed.** No cross-build, signing, keychain operation, install,
  network request, `xcode-select`, `sudo`, staging, or commit was performed.
- Build authorization: decision 46 and the explicit ticket implementation
  request granted approval before the first build.

Built the minimal `Frisket` package: a static `FrisketCore` library, one
`FrisketCoreTests` target, macOS 26 minimum, native architecture by default,
no external dependencies and no speculative capture behavior. Added the four
static checks and an empty application-port ledger at `docs/ported-files.json`.
See [the package guide](../../../docs/core-package.md) for scan scope, retained
header/provenance format, known lexical limitations, and repeatable commands.
Identity scrubbing covers product inputs; accepted research, ADRs, tickets,
development skills, and planted test fixtures remain outside product identity.

Verification commands and outcomes (from repository root):

```sh
uname -m
sw_vers
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift --version

export DEVELOPER_DIR=/Library/Developer/CommandLineTools
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"

swift build --disable-sandbox --disable-keychain \
  --cache-path .build/cache --scratch-path .build \
  --config-path .build/config --security-path .build/security

swift test --disable-sandbox --disable-keychain --disable-xctest \
  --cache-path .build/cache --scratch-path .build \
  --config-path .build/config --security-path .build/security

swiftc -frontend -parse Tests/FrisketCoreTests/ToolchainTests.swift \
  Tests/FrisketCoreTests/RepositoryChecksTests.swift

file .build/x86_64-apple-macosx/debug/FrisketCore.build/FrisketCore.swift.o

for check in dependencies imports identity provenance; do
  /usr/bin/python3 Checks/check_repository.py --root . --check "$check" || exit
done
for fixture in Checks/Fixtures/*.json; do
  /usr/bin/python3 Checks/check_repository.py --fixture "$fixture" || exit
done
```

- `swift build`: **passed**. Test-source syntax parse: **passed**, not a
  substitute for typechecking or running Swift Testing.
- Full `swift test`: **attempted once**, failed at `import Testing`; **0 tests
  executed**. Final source contains 3 Swift Testing declarations / 18 cases
  (1 toolchain probe, 4 live checks, 13 fixture cases), all unexecuted.
- Standalone checks: **4/4 live checks passed; 13/13 fixtures passed** after
  review fixes. An additional offline `dump-package` probe using a real manifest
  with the official GRDB URL passed the allowlist without fetching GRDB.
- TDD evidence: first probe failed with missing `Package.swift`; after creating
  the package, filtered runs exposed cache restrictions, then the unavailable
  `Testing` module. Filtered commands used
  `--filter commandLineToolsRunSwiftTestingOnSupportedMacOS` (the probe's
  original name) and `--filter dependencyAllowlistRejectsOtherPackages`.
  Each static check's rejection fixture first exited 1 against an empty check,
  then passed after implementation. Qualified-GRDB and review-discovered
  interpolation regressions also received failing fixtures before fixes.
- Cache workaround: the original attempt failed on the user SwiftPM/Clang
  caches. Repo-local cache/scratch/config/security paths cleared those errors;
  nested SwiftPM sandboxing then failed with
  `sandbox-exec: sandbox_apply: Operation not permitted`. `--disable-sandbox`
  cleared that failure inside the still-active agent filesystem sandbox.

Pocock code review ran independent Codex Standards and Spec agents against this
ticket's changes (new files compared with an empty baseline; the repository
was unborn when work started). **Standards: 1 P2 finding, fixed** — executable
string interpolations were initially masked, hiding qualified GRDB references.
A red-first fixture now covers normal and raw interpolation; the reviewer
rechecked the fix and found no introduced issue. **Spec: 0 substantive
findings**; the explicit Xcode-only fallback satisfies the probe criterion.
Final ticket bookkeeping completed here. Ticket 01's notices and `.gitignore`
were not edited. Coordinator retains commit ownership.
