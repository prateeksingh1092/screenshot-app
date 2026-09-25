# Ticket 40 verification draft

Model: Cursor coordinator chat (Claude Opus 5.5 High). Not a v1 declaration.
Codex assessment is still required and is unavailable until 2026-09-29 11:57.
x86_64 only; arm64 not executed.

## Automated evidence

- Root `swift test` after the own-process listing fix (2026-09-23 21:12 CDT):
  **296 tests in 44 suites**. One known `HistoryRecoveryTests` `.rootLocked`
  flake failed in the full run and passed on an isolated re-run. New
  `ScreenCapturePolicyTests` (3) passed. First-run and Performance Python
  unittests passed (4 + 15).
- Performance dry-run wrote `.build/performance/dry-run.md`. Labelled
  **synthetic, not a baseline**. No 20-run idle or latency session started.
  `pmset gpuswitch` remains `2` (unchanged).
- Ticket 36 peak on 5120×57,600: **586,006,528** bytes, under 2 GB.
- Ticket 33 Vision pair on Version 26.7 (Build 25G229): CANARY (6) unredacted,
  0 after redaction.

## Capture fix (unlisted own process)

`ScreenCapturePolicy.filter` used to fail closed unless this process's PID
appeared in `SCShareableContent.applications`. After the overlay hides,
`onScreenWindowsOnly` snapshots omit the LSUIElement app, so every accept
returned “Capture unavailable”. Unlisted is now allowed; a listed bundle
with a different PID still fails closed. Tests:
`Tests/FrisketAdapterTests/ScreenCapturePolicyTests.swift`.

## Signed Development install (2026-09-23 21:13 CDT)

Sole path: `/Users/16intelmac/Applications/Frisket.app`.

- Identifier `io.github.prateeksingh1092.frisket.debug`
- Team `9M43Q952NK`
- Authority Apple Development: `prateeksingh1092@gmail.com (DP3ZVUC5Y6)`
- Thin `x86_64`, hardened runtime, empty entitlements
- CDHash `8414521e88861a8126204d42bea70f0c79b11cd4`
- `codesign --verify --strict` passed
- Includes the policy fix, AX thumbnail window, status-menu Copy/Delete
  Latest, and Settings/History `orderOut` at launch
- Previous 11:33 install moved aside under `.build/`
- Production Release (`io.github.prateeksingh1092.frisket`) was not
  installed or launched

## Live synthetic capture (2026-09-23 21:14–21:17 CDT)

Pattern helper only. No real-content captures kept in the repo.

- Area, built-in 2×: 640×360, `FrisketTestPattern --verify` PASS
- Area, external 1×: 320×180, `--verify` PASS
- Full screen, built-in 2×: 3584×2240, `--verify-full` PASS
- Esc after overlay: no thumbnail
- Status-menu **Copy Latest Capture** and **⌃⌥⌘T** then `c` both wrote
  `public.png` (pasteboard changeCount advanced) and verified
- Successful Copy removed the thumbnail
- History gained finalized rows for Copy and one 10s auto-dismiss

## First-run record (pixel-free)

`.build/first-run/record.json` (gitignored), `status: partial`.

- macOS 26.7 (25G229), commit `16e8e3e0fc4e`, `x86_64`, `arm64_executed: false`
- Displays: built-in Retina 3584×2240 / 1792×1120; external 1920×1080 / 1920×1080
- **10 pass:** granted, rebuilds 1–2, built-in, external 1×, Esc, area /
  full-screen / focus shortcuts, pattern verify
- **4 blocked** (no unused TCC account): not-asked, denied, revoked-while-running,
  needs-relaunch
- **7 pending:** after-resign, negative coordinates, unplug, overlay over
  fullscreen, overlay across Space, Full Keyboard Access, VoiceOver

## Ticket 09 backup exclusion

`tmutil isexcluded` reports **Excluded** for
`~/Library/Application Support/io.github.prateeksingh1092.frisket.debug/History.noindex`.

## Still open (not a pass)

- Remaining first-run cases above. VoiceOver, Full Keyboard Access, unplug,
  Space/fullscreen overlay, and isolated TCC still need Prateek or a spare
  account.
- Live performance vs ratified targets (tickets 37/38). Placeholders stand.
  Do not change GPU policy.
- Codex assessment of this report after 2026-09-29 11:57.

## C3 label (after keychain unlock)

`arm64 built and signed, never executed`. Architectures `arm64`+`x86_64`.
Identifier `io.github.prateeksingh1092.frisket`. Team `9M43Q952NK`. CDHash
`c273fe80a1c0fe7cc1fbf6e0f818cd8cce93772d`. `distributed: false`.
`arm64_executed: false`. `codesign --verify --strict` passed. Not launched,
not installed, not distributed.

Nothing in this draft is a distribution or Apple-silicon runtime claim.
