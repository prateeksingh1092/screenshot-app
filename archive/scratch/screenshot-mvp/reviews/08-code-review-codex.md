## Standards

- **Nit — [check_repository.py:173](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-08/Checks/check_repository.py:173):** The guard rejects event taps/global monitors but does not enforce exactly one Carbon hot key. Current code registers one; add a duplicate-registration rejection case. The Xcode phase runs every build and propagates failures.

Lifecycle ownership remains in `FrisketCore`; adapters handle platform operations and presentation. Adapter tests exercise commands and observable effects through injected seams. No tracked caches or stray outputs were found.

## Spec

- **Should-fix — [ThumbnailPanel.swift:62](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-08/Frisket/ThumbnailPanel.swift:62):** “Focus Latest Thumbnail” only makes the panel key; it does not explicitly move focus to Copy or establish a visible focus indicator. Copy has a VoiceOver label and a C shortcut, but Tab/Space reachability remains unverified. Set explicit Copy focus, retain its visible indicator, and check Tab, Space, C and VoiceOver.

- **Should-fix — [FrisketTestPattern.swift:51](/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.worktrees/ticket-08/Tools/FrisketTestPattern.swift:51):** The colour fixture assumes its authored sRGB values survive display rendering within ±3, without controlling the window’s colour space. **Most likely cause: the helper’s sRGB → display-profile → sRGB conversion**, rather than pasteboard encoding; this remains an inference. Capture requests sRGB, ImageIO encodes PNG, and Copy passes those bytes unchanged. The verifier correctly converts into sRGB RGBA; its tolerance detects the mismatch but does not cause it. Set the helper window’s [colour space](https://developer.apple.com/documentation/appkit/nswindow/colorspace) explicitly to sRGB, then compare the direct captured PNG with the pasted PNG before Preview export. Do not simply widen tolerance to 22; investigate capture conversion if the controlled fixture still fails.

Other requested checks pass by inspection:

- Prefetch starts before selection; overlays are ordered out and transactions flushed before capture.
- Selection and capture geometry stay on one display. The filter positively identifies Frisket’s PID and excludes its application, failing closed without window-sharing fallback.
- Clipboard output is PNG plus concealed metadata, current-host-only. No general-clipboard content reads; `changeCount` is metadata.
- The reserved storage root derives from the `.debug` bundle identifier. Entitlements are empty, hardened runtime is enabled, and signing/install instructions specify one identity and path. Permission identity should remain stable; two-rebuild persistence remains untested.
- Decisions 49/50 were read from `main`, since the snapshot ends at 48. Decision 49 permits pending manual checks.

Verification: **22 tests passed; unsigned Xcode build succeeded.** No source edits, launch, signing, capture or clipboard use.

Verdict: fix-then-merge