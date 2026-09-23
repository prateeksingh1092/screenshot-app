# 02: Core package skeleton and toolchain probe

**What to build:** a Swift package for Frisket's core logic that builds and tests without Xcode, proving `swift test` with Swift Testing works under the installed Command Line Tools, plus the static checks every later ticket relies on.

**Blocked by:** None (can start immediately)

**Status:** claimed

- [ ] The package targets macOS 26 and builds for the native architecture only.
- [ ] One Swift Testing test runs green under `swift test` with the Command Line Tools; if it can't, the blocker is reported accurately and the test is marked Xcode-only.
- [ ] Static check: the only allowed dependency is GRDB (no networking, analytics, updater, or image-format libraries).
- [ ] Static check: core modules never import AppKit, SwiftUI, or concrete GRDB types outside the storage adapter.
- [ ] Static check: Snapzy's name or author appears nowhere outside licence headers and notices.
- [ ] Static check: every ported file keeps its licence header and has a provenance entry.
- [ ] The verification report states the architecture and OS it ran on and that arm64 was not executed.
- [ ] Running the build needs Prateek's approval at the time.

## Comments
