# 06: Capture to Copy through the command layer

**What to build:** in the core package, a capture command produces a Pending capture from a fixture pixel source and a Copy command delivers it to a recording clipboard stand-in, all through the command layer and the Capture lifecycle coordinator. Verified entirely by `swift test`, no app or Xcode needed.

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] Commands take typed capture identifiers and explicit inputs and return UI-independent results.
- [ ] The coordinator reports commit outcomes and delivery outcomes separately; a delivery retry refers to the same revision.
- [ ] Duplicate and stale commands (unknown or already-discarded capture) are rejected safely with a typed result.
- [ ] A global budget for pending bytes is tracked and a capture beyond it is refused with a typed result.
- [ ] The clipboard port accepts image data only; tests assert that no file location is ever written and the port has no read operation.
- [ ] Diagnostics: a logging interface accepting only events from a closed set, an error domain and code, and fields from a fixed allowed set; 7-day local retention; a planted-secret test proves pixels, text, and paths can't reach the log.
- [ ] Nothing is written under the app-owned root by capture or copy.

## Comments
