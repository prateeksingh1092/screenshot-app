# Ticket 14 implementer report

Model/tool: Cursor coordinator chat (Claude Opus 5.5 High). Codex and Cursor Other Models remain past included-usage limits. No delegated inference.

Environment: x86_64, macOS 26.7, Xcode 26.5 toolchain. arm64 not executed.

Implemented thumbnail system events and the auto-dismiss setting at seam 1:

- `ThumbnailAutoDismiss.after(Duration)` / `.never`. Zero seconds expire immediately; never is a separate persisted flag (`ThumbnailAutoDismissPreference`). Overflow still finalizes under never.
- `setThumbnailPolicy` applies a new delay or never to cards already on the stack.
- `handleSystemEvent(.quit)` finalizes unedited pending cards oldest first and stops on the first failed commit.
- `screenLocked` / `screenUnlocked` pause and resume timeout the same way stack focus does; overflow stays due.
- `assignThumbnailDisplay` plus `displaysChanged(remaining:)` move cards off a removed display onto `remaining.first` without finalizing.
- Unedited pending captures write nothing (decision 31); a crash therefore loses them.
- Settings persist never and seconds separately, offer the control next to History, and push the policy live.

TDD: red compile for `autoDismiss: .never`, then green never/zero/preference/policy, then quit, lock, unplug, and crash slices. `ThumbnailStackCommandsTests`: 20 passed.

Validation: **246 tests / 36 suites passed**. Unsigned x86_64 `xcodebuild` succeeded (`CODE_SIGNING_ALLOWED=NO`). Manual: `docs/manual-checks/14-thumbnail-system-events.md` (quit, lock, unplug, Settings persist; not run).

Stopped before review. Ticket Status/checkboxes unchanged.
