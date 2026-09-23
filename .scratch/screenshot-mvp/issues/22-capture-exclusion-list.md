# 22: Capture exclusion list

**What to build:** in Settings, Prateek lists apps (such as a password manager) whose windows are always left out of every capture.

**Blocked by:** 08, 11

**Status:** resolved (tested on `main` at `cd0dd99`; listed-app-on-screen manual pending)

- [x] The list is empty by default (decision 37).
- [x] Every capture mode applies the list through the capture content filter alongside Frisket's self-exclusion.
- [x] App names never reach logs.
- [x] Seam 1 test asserts the filter passed to the capture source; manual check with a listed app on screen.

## Comments

- **Integration:** `integrate/16-22-24` fast-forwarded `main` to `cd0dd99`. Area, full-screen, and window listing all apply the exclusion list plus Frisket self-exclusion (`owner.bundleIdentifier` is non-optional). `swift test`: 210 tests in 31 suites passed. Unsigned x86_64 `xcodebuild` succeeded. x86_64 only; arm64 not executed. Coordinator chat after Codex/Other Models limits.
