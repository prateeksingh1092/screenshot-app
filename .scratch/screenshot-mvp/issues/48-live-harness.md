# 48: Live harness in the repository

**What to build:** The live checks that found D1–D26 can be rerun from the repository. The harness has:

- a pattern window with a display choice and a scroll page that opens at its top;
- a focus-guarded driver that types only into Frisket or the pattern and checks every point against all displays;
- pixel meters for blocks and ink bands;
- a beta-matrix script that runs the plan's §1.2 live rows, saves and restores the clipboard, and writes a pass/fail report without personal pixels.

**Blocked by:** 43

**Phase:** 0

**Status:** ready-for-agent

- [ ] The harness tools build from the repository with one command, and `ci.sh` compiles them without running them.
- [ ] The driver refuses to send keys unless Frisket or the pattern window is frontmost, and refuses points outside every display.
- [ ] The scroll page opens at its top.
- [ ] The beta matrix covers area, window, full-screen and scrolling capture (steady and flick); editor marks (arrow, label, Solid redaction, Blur, Magnify, crop); Copy Text with and without text; the Thumbnail stack; History Copy, Save and Delete; ⌘⇧2 focus; and a top-row pointer on both displays. Each row names its defect ID, and rows for open defects are expected failures.
- [ ] The clipboard is saved and restored around every run. Evidence is cropped to the test windows and kept out of git.
- [ ] A README beside the tools records the key codes and gotchas from the handoff.
- [ ] One unattended run of the matrix is recorded. It drives the real screen, so it runs only when Prateek says he is away.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
