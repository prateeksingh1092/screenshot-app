# 41: App target sources as a synchronized folder

**What to build:** `Frisket.xcodeproj` picks up the app target's sources from the `Frisket/` folder through a `PBXFileSystemSynchronizedRootGroup`, as the `FrisketCore` target already does. Adding or removing an app source file then no longer edits `project.pbxproj`, so parallel app tickets don't conflict there.

**Blocked by:** 08

**Status:** resolved (tested on `main` at `7c1b87d`)

- [x] The app target's Swift sources come from one synchronized root group over `Frisket/`. The per-file `PBXFileReference` and build-file entries for those sources are gone.
- [x] `Info.plist` and `Frisket.entitlements` are excluded from membership, with a build-file exception set, so they aren't copied as resources. Their build-setting paths are unchanged.
- [x] The built app is equivalent: same bundle identifier, entitlements, hardened runtime, Info.plist keys, and "Reject Event Taps and Global Monitors" build phase. The unsigned build succeeds, and the root suite and static checks pass. (Signed entitlement embedding is checked at the next signed build.)
- [x] `docs/app-build.md` states that new app source files need no project-file edit.

## Comments

### 2026-09-23 — coordinator: created

Prateek directed this at 01:05 before the post-08 batch of app tickets (09, 19, 20, then 18, 21, 23). Rationale: those tickets all add app sources. With explicit file references, every one of them edits `project.pbxproj` and conflicts at integration. Build hygiene only; no product behaviour changes.

### 2026-09-23 — coordinator: resolved

- **Implementer:** Codex GPT-6 Astra, high. Report: `reports/41-implementer.md`; evidence: `41-build-evidence.json`.
  - Before and after the change, the unsigned builds compile the same 9 app and 7 core sources, and all 23 Info.plist keys match.
  - A temporary Swift file compiled without any project edit.
  - A new repository check rejects explicit app-source references.
- **Review:** fresh Codex, `reviews/41-code-review-codex.md`: no findings, verdict merge.
- **Integration:** `integrate/41` passed the root `swift test` (58 tests in 8 suites) and the unsigned `xcodebuild`. x86_64 only; arm64 not executed.
