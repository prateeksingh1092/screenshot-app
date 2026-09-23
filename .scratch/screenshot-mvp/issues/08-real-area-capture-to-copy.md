# 08: Real area capture to a thumbnail to Copy

**What to build:** Frisket runs as a menu-bar app; a global shortcut starts an area selection on the current display, the capture appears as a floating thumbnail, and its Copy action puts the image on the clipboard. This is the first signed, launched build.

**Blocked by:** 06, 07

**Status:** resolved (tested on `main` at `ad2b253`; manual items pending Prateek, decision 49)

- [x] The app is a development build with the `.debug` bundle identifier, its own storage root, and its own permission identity; every app-owned path derives from the bundle identifier.
- [x] One Carbon hot key starts capture; no event taps and no global mouse monitors while idle (static check).
- [ ] (Pending manual drag and edge checks) Single-display area selection by dragging; overlays are hidden before pixels are taken.
- [x] ScreenCaptureKit captures with a content filter that excludes Frisket's own app; no fallback relying on window sharing flags.
- [x] Shareable content is prefetched when the shortcut fires.
- [ ] (Pending manual keyboard and VoiceOver check) The thumbnail appears on the capture display, built by downsampling the in-memory image; its Copy control has a VoiceOver label and is keyboard-reachable.
- [x] Copy writes image data only, restricted to this Mac, marked concealed for clipboard managers; Frisket never reads the general clipboard.
- [x] Hardened runtime, minimal entitlements written fresh (no network, no debugging entitlement on the installed build), one fixed install path.
- [ ] (Pending manual check) A Screen Recording grant survives two rebuilds.
- [x] Build, launch, screen capture, and clipboard use need Prateek's approval at the time.

## Comments

### 2026-09-23 — coordinator: resolved (manual items pending)

- **Implementer:** Codex GPT-6 Astra, high. Report: `reports/08-implementer.md`, which includes the manual evidence and the Fix pass.
- **Review:** fresh Codex, `reviews/08-code-review-codex.md`, verdict fix-then-merge.
- **Fix pass:** one Codex session (01a0ccd6).
  - Focus Latest Thumbnail now focuses Copy, with a visible outline.
  - The test-pattern window draws in sRGB.
  - The static check rejects a second hot-key registration.
- **Manual results with Prateek (00:15–00:35):**
  - Pass: launch, Screen Recording grant, 640×360 capture at 2×, Copy by pointer.
  - Colour: FAIL, blue 22,0,255. This was before the sRGB helper fix; rerun needed.
- **Integration:** `integrate/08` passed the root `swift test` (58 tests in 8 suites) and the unsigned `xcodebuild`. x86_64 only; arm64 not executed.
- **Still pending for Prateek:**
  - colour rerun;
  - keyboard Copy, focus and VoiceOver;
  - drag selection and the display-edge clamp;
  - Esc cancellation without activating Frisket;
  - ⇧⌘3/4/5/6 staying with macOS;
  - external-display capture;
  - grant persistence across two signed rebuilds.
  Steps: `docs/manual-checks/08-first-launch.md`.
- **Launch note:** the first fix-pass launch ran inside Cursor's sandbox and failed with "Operation not permitted", because shell redirections break the allowlist match. It was relaunched with the brief path as the prompt argument.
