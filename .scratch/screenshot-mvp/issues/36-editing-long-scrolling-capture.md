# 36: Editing a long scrolling capture

**What to build:** Prateek opens a very tall scrolling capture in the editor, redacts and annotates it, and the result renders and saves without exhausting memory.

**Blocked by:** 26, 35

**Status:** in-progress (branch `ticket/36-editing-long-scrolling`)

- [ ] The editor works on a tiled or downsampled proxy.
- [ ] Rendering and PNG encoding proceed strip by strip.
- [ ] Solid redaction guarantees hold at full resolution: canary cases on a tall synthetic capture.
- [ ] Peak memory while editing and saving the 5120×57,600 synthetic capture is measured and recorded.

## Comments

### 2026-09-23 — coordinator

Claimed on `5c0396f` after ticket 33 closed. Coordinator chat implements (Codex/Other Models still limited). Branch `ticket/36-editing-long-scrolling`.
