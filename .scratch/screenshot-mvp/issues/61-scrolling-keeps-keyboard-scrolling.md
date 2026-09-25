# 61: The page keeps keyboard scrolling during a scrolling capture

**What to build:** During a scrolling capture, Frisket's panel never takes keyboard focus, so Page Down, Space and the arrow keys scroll the page. Pressing ⌘⇧6 again finishes the capture as Done. Cancel stays reachable with VoiceOver, and Esc works once the user clicks the panel. No global monitors are added (D11, DA-9, story 92).

**Blocked by:** 48

**Phase:** 1

**Status:** resolved (tested on `main`; live row waits for an approved install)

- [x] Preview updates never make the panel key.
- [x] ⌘⇧6 during a scrolling capture means Done; with no scrolling capture running, it starts one.
- [x] The input-monitoring check stays green.
- [ ] Live scrolling row: Page Down scrolls the pattern page during a capture.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: coordinator, implemented

- **Implementer:** the coordinator (Claude Opus 5.5, Claude Code, high effort).
- **Panel:** `ScrollingSessionPanel.update` no longer calls `makeKey`, or `makeFirstResponder`, on each preview. The panel stays non-activating and can become key on a click, so Esc and Return work after the user clicks it. Cancel and Done stay VoiceOver buttons.
- **⌘⇧6:** `ManualScrollingCapture` gains `isRunning` and `finish()`. `FrisketApp.captureScrolling` calls `finish()` when a session runs; otherwise it starts one. No global monitor was added, and the input-monitoring check is green.
- **Tests:** `finishDuringASessionMeansDoneAndDoesNothingOtherwise` is new. `ci.sh` is green: 327 tests.
- **Live:** the `scroll-keys` row now expects pass. The harness's scrolling rows still finish with the Done button; a row for ⌘⇧6-as-Done is to be added at the next live run.
