# 36: Editing a long scrolling capture

**What to build:** Prateek opens a very tall scrolling capture in the editor, redacts and annotates it, and the result renders and saves without exhausting memory.

**Blocked by:** 26, 35

**Status:** ready-for-agent

- [ ] The editor works on a tiled or downsampled proxy.
- [ ] Rendering and PNG encoding proceed strip by strip.
- [ ] Solid redaction guarantees hold at full resolution: canary cases on a tall synthetic capture.
- [ ] Peak memory while editing and saving the 5120×57,600 synthetic capture is measured and recorded.

## Comments
