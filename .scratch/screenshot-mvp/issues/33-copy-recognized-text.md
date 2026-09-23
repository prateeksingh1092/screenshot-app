# 33: Copy recognized text

**What to build:** Prateek copies the text in a capture, recognized from the rendered result, so redacted text is never extracted.

**Blocked by:** 26

**Status:** ready-for-agent

- [ ] Vision runs only on the rendered revision; results for a stale revision are dropped.
- [ ] The notification says only "Copied N characters".
- [ ] Recognized text is never stored or logged.
- [ ] Seam 1 tests use a text-recognition stand-in.
- [ ] A tagged, local-only real Vision pair: canary text recognized when unredacted, absent once redacted; the OS build is recorded.

## Comments
