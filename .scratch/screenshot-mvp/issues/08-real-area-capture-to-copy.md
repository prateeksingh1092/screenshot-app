# 08: Real area capture to a thumbnail to Copy

**What to build:** Frisket runs as a menu-bar app; a global shortcut starts an area selection on the current display, the capture appears as a floating thumbnail, and its Copy action puts the image on the clipboard. This is the first signed, launched build.

**Blocked by:** 06, 07

**Status:** in-progress (branch `ticket/08-real-area-capture`)

- [ ] The app is a development build with the `.debug` bundle identifier, its own storage root, and its own permission identity; every app-owned path derives from the bundle identifier.
- [ ] One Carbon hot key starts capture; no event taps and no global mouse monitors while idle (static check).
- [ ] Single-display area selection by dragging; overlays are hidden before pixels are taken.
- [ ] ScreenCaptureKit captures with a content filter that excludes Frisket's own app; no fallback relying on window sharing flags.
- [ ] Shareable content is prefetched when the shortcut fires.
- [ ] The thumbnail appears on the capture display, built by downsampling the in-memory image; its Copy control has a VoiceOver label and is keyboard-reachable.
- [ ] Copy writes image data only, restricted to this Mac, marked concealed for clipboard managers; Frisket never reads the general clipboard.
- [ ] Hardened runtime, minimal entitlements written fresh (no network, no debugging entitlement on the installed build), one fixed install path.
- [ ] A Screen Recording grant survives two rebuilds.
- [ ] Build, launch, screen capture, and clipboard use need Prateek's approval at the time.

## Comments
