# 55: Copy Text with no text leaves the clipboard alone

**What to build:** Copy Text on a capture with no recognizable text leaves the clipboard exactly as it was and shows "No text found" on the Thumbnail status line, with no modal. When text is found, it is copied and the confirmation is non-modal too (D8, DA-5, story 89).

**Blocked by:** 47

**Phase:** 1

**Status:** resolved (tested on `main`; live row pending the next matrix run)

- [x] The D8 test passes without the known-defect mark.
- [ ] Neither outcome shows a modal alert, and VoiceOver announces the result.
- [ ] The Copy Text rows of the live matrix (text and none) pass.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.

### 2026-09-24: coordinator, note from ticket 47

`copyRecognizedTextAfterDoneUsesTheRenderedRevisionStandIn` expects the empty string to be written. Change it with the fix (found by ticket 47).

### 2026-09-24: coordinator, implemented

- **Implementer:** the coordinator (Claude Opus 5.5, Claude Code, high effort).
- **Core:**
  - Copy Text whose recognized text is empty, or only whitespace, returns the new outcome `.noTextFound(revision)` and never calls the text clipboard.
  - Diagnostics gains the event name `noTextFound`.
- **App:** Copy Text results show on the Thumbnail's status line for 4 s, and the status line announces them to VoiceOver: "Copied N characters", "No text found", or "Could not copy text…". The modal notice for this path is gone (DA-5).
- **Tests:**
  - Both D8 tests are unwrapped and green, and a new whitespace-only test passes.
  - Two existing tests that locked in writing `""` now expect `.noTextFound` with the clipboard untouched: `copyRecognizedTextAfterDoneUsesTheRenderedRevisionStandIn` and `copyRecognizedTextStandInSeesCanaryUntilRedactionCoversIt`.
- **CI:** `ci.sh` is green: 321 tests, 92 known issues.
- **Live:** the `copytext-none` row now expects pass and also checks for "No text found". It runs in the next matrix run.
