# 35: Scrolling capture

**What to build:** Prateek starts a scrolling capture, scrolls the page himself while a live preview builds, and gets one tall image as a thumbnail he can copy or keep in History.

**Blocked by:** 09, 34

**Status:** resolved (tested on `main` at `f9dbbb2`; live `--show-scroll` manual pending)

- [x] Manual scrolling only; no Accessibility permission (decision 32).
- [x] The pending original is held as compressed strips in memory; frames are released promptly.
- [x] A new scrolling capture is refused when the global pending-byte budget is exceeded.
- [x] Reaching the pixel cap or memory budget stops the capture with a clear message; the cap is set from the trial's measurements.
- [x] The result flows to thumbnail, Copy, and History through the command layer.
- [x] Peak memory is measured and recorded on this Mac.

## Comments

- **Integration:** `integrate/35-38` fast-forwarded `main` to `f9dbbb2`. Scrolling sits beside window capture, exclusions, remappable shortcuts, retention, editor, and drag. Accepted scrolling results enter the thumbnail stack. Synthetic peak from the implementer: 221,888,512 bytes. Root `swift test`: 234 tests in 36 suites passed. Unsigned x86_64 `xcodebuild` succeeded. x86_64 only; arm64 not executed. Coordinator chat after Codex/Other Models limits.
