# 45: Red tests: choosing what to capture

**What to build:** Tests pin down how Frisket chooses what to capture. The cursor window (empty owning-app bundle ID, very high window level) is never chosen over the window under it (D2). A Selection that starts on a display's top pixel row or leftmost column has an Origin display (D14). The Capture exclusion list and Frisket's own windows stay out of area, full-screen, window and scrolling captures.

**Blocked by:** 43

**Phase:** 0

**Status:** ready-for-agent

- [ ] D2, through `WindowSelection`: with a cursor-like window above a normal window, the normal window is picked.
- [ ] D2: when no window can be picked, the failure names that cause, not "smaller area".
- [ ] `foreignFloatingWindowIsCapturedAheadOfOverlappingNormalWindow` stays green.
- [ ] D14: a pointer on a display's top pixel row or minimum x gets that display as its Origin display.
- [ ] For each of the four capture modes, the content filter excludes Frisket and every app on the Capture exclusion list. These are regression guards and are green today.
- [ ] The D2 and D14 tests are marked as known defects.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
