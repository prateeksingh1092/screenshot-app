# 36: Editing a long scrolling capture

**What to build:** Prateek opens a very tall scrolling capture in the editor, redacts and annotates it, and the result renders and saves without exhausting memory.

**Blocked by:** 26, 35

**Status:** resolved (tested on `main` at `4e109cf`; tall-scroll editor canvas manual pending)

- [x] The editor works on a tiled or downsampled proxy.
- [x] Rendering and PNG encoding proceed strip by strip.
- [x] Solid redaction guarantees hold at full resolution: canary cases on a tall synthetic capture.
- [x] Peak memory while editing and saving the 5120×57,600 synthetic capture is measured and recorded.

## Comments

### 2026-09-23 — coordinator

Claimed on `5c0396f` after ticket 33 closed. Coordinator chat implements (Codex/Other Models still limited). Branch `ticket/36-editing-long-scrolling`.

### 2026-09-23 — implementer

Report: [36-implementer.md](../reports/36-implementer.md). Strip render/encode,
downsampled editor proxy, tall canary, and a 586 MB peak on the 5120×57,600
edit. Manual not run. Status/checkboxes unchanged pending review.

### 2026-09-23 — review

In-chat review vs `05bce68`: [36-code-review.md](../reviews/36-code-review.md). One justified
fix: Done streams the pending PNG in strips instead of decoding a full base
bitmap.

- **Integration:** `integrate/36` fast-forwarded `main` to `4e109cf`. The
  editor paints a 2048-edge ImageIO proxy; render and Done walk 256-row
  strips into `StripPNGEncoder`. After review, Done streams ImageIO slices
  and never allocates a full base `Bitmap`. Tall 16×96 canary through Done;
  5120×57,600 peak **586,006,528** bytes. Root `swift test`: 291 tests in
  43 suites passed. Unsigned x86_64 `xcodebuild` succeeded
  (`CODE_SIGNING_ALLOWED=NO`; GRDB SourcePackages reused after a fresh
  checkout timed out on the unused SQLiteCustom submodule). x86_64 only;
  arm64 not executed. Coordinator chat after Codex/Other Models limits.
  Manual tall-scroll editor canvas remains for Prateek.
