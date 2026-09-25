# Frisket v1: specification

Status: ready-for-agent

Sources: accepted decisions 1-43 in `decisions.md` (including the 57 red-team amendments adopted there), the glossary in `../../CONTEXT.md`, and `../../docs/adr/0001-build-fresh-snapzy-as-reference.md`. Where this spec and a decision disagree, the decision wins; report the conflict.

## Problem Statement

Prateek takes screenshots all day on an Intel MacBook Pro running macOS 26 and needs to share them quickly without leaking what is in them. The built-in macOS tool captures well but has weak annotation, no real redaction, no scrolling capture, and no searchable recent history. Commercial tools add those features but tie them to cloud accounts, uploads, update feeds, and telemetry he doesn't want. The open-source option he evaluated, Snapzy, keeps unredacted originals on disk, treats redaction as a styled rectangle or a blur that reads the original, leaks file names into logs and clipboard, and depends on capture APIs that don't hold at a macOS 26 minimum. He wants a fast, local-only, keyboard-friendly capture tool whose redaction he can trust.

## Solution

Frisket is a native macOS menu-bar app that captures an area, a window or the full screen as a still image (scrolling capture was removed by decision 60). Each capture appears as a floating thumbnail he can copy, save, drag, edit, or delete with the mouse or the keyboard. The editor adds annotations and solid redaction, and whatever leaves the editor is a flattened image in which redacted pixels are gone. Unedited and pending captures live only in memory; only finalized, flattened images reach disk, in a local History that keeps 30 days or 1 GB, whichever comes first. Text recognition runs on the rendered result, so redacted text can't be extracted. Nothing leaves the Mac: no accounts, network features, update feed, or telemetry.

## User Stories

### Capturing

1. As a user, I want to capture a selected area with a global shortcut, so that I can grab exactly what I need.
2. As a user, I want to capture a single window by clicking it, so that I get a clean image of that window alone.
3. As a user, I want to capture the full screen of a display, so that I can record everything visible at once.
4. **Retired (decision 60).** As a user, I want to capture a page longer than the screen by scrolling it myself, so that I get one tall image of a chat or document.
5. As a user, I want a crosshair on every display during area selection, so that I can start a selection wherever the content is.
6. As a user, I want a pixel magnifier while selecting, so that I can place edges precisely.
7. As a user, I want Shift to lock an axis, Option to grow from the centre, Space to move the selection, and arrow keys to nudge it, so that selecting feels like the built-in tool.
8. As a user, I want Esc to cancel a selection even though Frisket isn't the active app, so that I can back out instantly.
9. As a user, I want an area selection to stay on the display where I started it, so that mixed-resolution displays never produce a distorted image.
10. As a user, I want a selection to cancel cleanly if a display is unplugged mid-selection, so that nothing half-captured is kept.
11. As a user, I want window highlighting to ignore Frisket's own panels, so that I never capture the tool itself.
12. As a user, I want Frisket's own thumbnails, editor, and History window to be absent from every capture, so that an earlier unredacted capture can't leak into a new one.
13. As a user, I want to list apps whose windows are always left out of captures, such as my password manager, so that their contents never enter an image.
14. As a user, I want window capture to cover the windows visible on my current Space, so that the behaviour is predictable.
15. As a user, I want the overlay to work over full-screen apps and after switching Spaces, so that capture works wherever I am.
16. **Retired (decision 60).** As a user, I want scrolling capture to show a live preview while I scroll, so that I can see the result building up.
17. **Retired (decision 60).** As a user, I want scrolling capture to stop with a clear message when it reaches its pixel or memory limit, so that I'm never surprised by a truncated image.
18. **Retired (decision 60).** As a user, I want scrolling capture to work without granting Accessibility permission, so that Screen Recording is the only permission Frisket needs.

### Shortcuts and permissions

19. As a user, I want Command–Shift and a number to capture — ⌘⇧3 full screen, ⌘⇧4 area, ⌘⇧5 window, ~~⌘⇧6 scrolling~~ (the ⌘⇧6 part is **Retired (decision 60)**; ⌘⇧6 is left free) — the same keys as the macOS screenshot tool, so that each key does exactly one thing.
20. As a user, I want to remap every shortcut, and be told when a mapping collides with an enabled system shortcut, so that I can set my own layout safely.
21. As a new user, I want onboarding to explain the Screen Recording permission, what History keeps and for how long, and that Save keeps a permanent copy, so that I know what Frisket stores.
22. As a user, I want Frisket to check permission before showing any overlay, so that I never draw a selection that can't be captured.
23. As a user, I want a recovery panel with "Open Privacy & Security" and "Quit & Reopen" when permission is missing, denied, revoked, or needs a relaunch, so that I can fix it in one step.
24. As a user, I want the menu-bar icon to show when permission is missing, so that I notice before trying to capture.
25. As a user, I want Frisket never to draw over a pending macOS screen-capture alert, so that system prompts stay visible.
26. As a user, I want my Screen Recording permission to survive rebuilds of Frisket, so that development doesn't keep re-prompting me.

### Floating thumbnail

27. As a user, I want each new capture to appear as a floating thumbnail on the display where I captured it, including over full-screen Spaces, so that I can act on it immediately.
28. As a user, I want to copy, save, drag, edit, or delete a capture from its thumbnail, so that most captures never need the editor.
29. As a user, I want a Delete capture action that skips History, so that a mistaken capture leaves no trace.
30. As a user, I want dismissing an unedited thumbnail to keep the capture in History, so that nothing I captured is lost by default.
31. As a user, I want the thumbnail to say "Kept in History", so that I know where a dismissed capture went.
32. As a user, I want to set thumbnail auto-dismiss to a delay or to never, so that thumbnails don't disappear before I act.
33. As a keyboard user, I want a shortcut that focuses the thumbnail stack, arrow keys to move between thumbnails, and single keys for copy, save, edit, delete, and dismiss, so that I never need the pointer.
34. As a VoiceOver user, I want each thumbnail announced when it appears and exposed with actions that don't depend on hovering, so that I can use every action.
35. As a user, I want auto-dismiss to pause while the stack has keyboard or VoiceOver focus, so that a thumbnail doesn't vanish while I'm using it.
36. As a user, I want every way a thumbnail can leave the screen (timeout, swipe, close, overflow, Esc, quit, display unplug, screen lock) to have one defined outcome, so that I can predict what is kept.
37. As a user, I want a crash to lose an unedited thumbnail's capture rather than write it to disk before I act, so that nothing reaches storage without my action.

### Editing and solid redaction

38. As a user, I want to open a capture in the editor from its thumbnail, so that I can annotate or redact it.
39. As a user, I want arrows, shapes, and text labels, so that I can point things out.
40. As a user, I want to crop a capture, so that I can remove what isn't needed.
41. As a user, I want a dedicated Solid redaction tool, separate from shapes, so that I can't accidentally make a see-through or rounded "redaction".
42. As a user, I want every pixel under a redaction to be exactly the fill colour and fully opaque in every output, at any display scale and after cropping, so that nothing hidden can be recovered.
43. As a user, I want effects that read pixels, such as blur or magnify, to see only the redacted image, so that an effect placed over a redaction can't reveal it.
44. As a user, I want Done, Copy, Save, or dragging from the editor to finalize the flattened result, so that what I share is exactly what I see.
45. As a user, I want closing the editor with edits to ask Finalize (default), Delete capture (destructive, never default), or Cancel (Esc), so that I choose deliberately.
46. As a user, I want Quit with editors open to show that same choice for each editor, so that quitting never silently keeps or loses my work.
47. As a user, I want a logout or restart that interrupts an unanswered prompt to discard that pending capture, so that nothing I didn't approve is saved.
48. As a user, I want the unredacted original never to be written to storage by Frisket, not even by autosave, window restoration, or image caches, so that it disappears when I finish.
49. As a user, I want the thumbnail to show the flattened result after I finalize, so that the original stops being displayed.

### Delivering

50. As a user, I want Copy to put only the flattened image on the clipboard, never a file location, so that pasting doesn't expose Frisket's storage.
51. As a user, I want copies to stay on this Mac and be marked so clipboard managers skip them, so that captures don't sync to my other devices or linger in clipboard history.
52. As a user, I want Frisket to replace a clipboard copy with the redacted result when I finalize a redaction, if I haven't copied anything else since, so that the clipboard doesn't keep an unredacted version.
53. As a user, I want Frisket never to read my clipboard, so that macOS never shows a paste-access alert.
54. As a user, I want Save to write a PNG to `~/Pictures/Frisket` by default, and to change that folder, so that exports go somewhere that isn't iCloud-synced unless I choose it.
55. As a user, I want Settings to warn me if my export folder is iCloud-synced, so that I know exports may leave this Mac.
56. As a user, I want dragging a capture into another app to hand over a copy, never Frisket's own file, so that dropping it on the Trash or moving it can't damage History.
57. As a user, I want exported files to be untouched by History retention and deletion, so that what I saved stays saved.
58. As a user, I want to copy the recognized text of a capture, taken from the rendered result, so that redacted text is never extracted.
59. As a user, I want the OCR notification to say only how many characters were copied, so that recognized text doesn't linger in Notification Center.

### History

60. As a user, I want a History window of my finalized captures, newest first, so that I can find a recent capture again.
61. As a user, I want to copy, drag, export, or delete any History item, so that History is a useful short-term archive.
62. As a user, I want History items to be finished images rather than re-editable documents, so that the pixel guarantees always hold.
63. As a user, I want History to keep captures for 30 days or up to 1 GB, whichever comes first, both configurable, with the oldest removed first, so that storage stays bounded.
64. As a user, I want a single capture larger than the 1 GB limit to be refused from History with a notice, while copy, save, and drag still work, so that the ceiling is never exceeded.
65. As a user, I want a one-time notice and a Settings line when captures were removed to stay under the size limit, so that eviction is never invisible.
66. As a user, I want deleting a History item to remove it immediately, not move it to the Trash, so that deletion means what it says.
67. As a user, I want History excluded from Time Machine and Spotlight, so that deleted captures don't live on in backups or search.
68. As a user, I want Frisket to be clear that it can remove captures only from itself, not from apps, devices, or backups it has already delivered to, so that I understand the privacy limits.
69. As a user, I want sudden clock changes not to wipe my History, so that a wrong date doesn't delete recent captures.
70. As a user, I want Frisket to recover cleanly after a crash or forced quit, with History exactly consistent with the files on disk, so that I never see a broken item.
71. As a user, I want capturing, copying, saving, and dragging to keep working if the History database can't be opened or upgraded, with a visible notice and a recovery option, so that a storage problem never blocks me.
72. As a user, I want History to survive renaming my home folder or restoring to another Mac, so that moving machines doesn't break it.
73. As a user, I want development builds to use their own permissions and History, separate from my installed copy, so that testing never touches my real captures.

### Privacy and diagnostics

74. As a user, I want Frisket to make no network connections, so that nothing about my captures leaves the Mac.
75. As a user, I want diagnostic logs kept locally for 7 days containing only event names and error codes, never pixels, recognized text, clipboard contents, file names, paths, app names, or window titles, so that logs can't leak what I captured.
76. As a user, I want the About window to show third-party notices, so that licences are honoured.

### Accessibility and performance

77. As a user, I want full keyboard operation of capture, the thumbnail, and the editor's controls, so that I can work without a pointer.
78. As a VoiceOver user, I want every control labelled, except the contents of the image canvas, so that I can use the app by ear.
79. As a user, I want the thumbnail to appear quickly after I finish a selection, so that capture feels instant.
80. As a user, I want Frisket to use almost no CPU while idle and to keep the low-power GPU, so that it doesn't drain battery or heat this Mac.
81. **Retired (decision 60).** As a user, I want a long scrolling capture to stay within a bounded amount of memory, so that it doesn't bog down my 16 GB Mac.

### Remediation behaviour (2026-09-24, decision 57)

These stories come from the live evaluation in `Plans/dreamy-giggling-barto.md`. Where they conflict with an earlier story or implementation decision in this spec, these stories win.

82. As a user, I want the saved, copied, and dragged image to match the editor preview exactly, so that what I see is what I share (D1, D23).
83. As a user, I want a label to keep every character I type, including lowercase and `$ . - %`, so that prices and versions stay correct (D6).
84. As a user, I want window capture to select the window under the pointer and never the cursor, and a failure message that names the real cause, so that window capture works (D2).
85. As a user, I want a click inside a selection to stay in Frisket and Esc to always cancel, so that I never click the app underneath by mistake (D4).
86. As a user, I want every selection to have an origin display, including when the pointer is on the top pixel row, so that a selection always starts (D14).
87. As a user, I want Done, Copy, and Save always visible in the editor, and ⌘C, ⌘S, and Return always to work, so that I can always finish an edit. The finish action is called "Done" everywhere (D5).
88. As a user, I want a cancelled drag to leave the capture pending with nothing on disk, so that only a completed drop finalizes it (D7, DA-3).
89. As a user, I want Copy Text on an image with no text to leave my clipboard unchanged and show a non-modal "No text found", so that I don't lose what I copied (D8, DA-5).
90. As a user, I want Thumbnails to be one fixed size and to stack without overlapping, so that I can see every pending capture (D9).
91. As a user, I want History Delete to ask for confirmation, and to close the capture's open Thumbnail first, so that deletion is deliberate and always succeeds (D10, DA-4).
92. **Retired (decision 60).** As a user, I want the page to keep keyboard scrolling during a scrolling capture, and ⌘⇧6 pressed again to finish it, so that I can scroll with the keyboard (D11, DA-9).
93. **Retired (decision 60).** As a user, I want a scrolling capture to reproduce the page exactly, to ask me to slow down when a scroll is too fast or ambiguous while keeping the part already captured, and to stop at 32,768 px, so that I never get a silently wrong image (D3, D20, DA-6).
94. As a user, I want ⌘⇧2 to move keyboard focus to the latest Thumbnail with a visible focus ring, so that I can act on it from the keyboard (D12).
95. As a user, I want Frisket to leave macOS settings unchanged, show which macOS screenshot shortcuts to turn off, link to System Settings, and restore them only when I ask, so that I stay in control of my Mac (D13, DA-2).
96. As a user, I want cropping never to leave a sliver of redacted content visible, so that Solid redaction always conceals (D18).
97. As a user, I want History row actions to work after "Try Again", so that recovery really recovers (D19).
98. As a user, I want to restore a History item to a Thumbnail with Copy, Save, Drag, and Copy Text but no Edit, so that I can reuse a finalized capture (DA-10, decision 28).
99. As a user, I want notices never to block me, and only destructive choices to ask, so that Frisket stays out of my way (DA-5).
100. As a user, I want the Loupe back while I choose a selection, so that I can place edges exactly (D26, story 6).
101. As a user, I want History and Settings to open on the active display with the right focus, the Thumbnail's accessibility name to say whether the capture is pending or finalized, Save to confirm, and exported file names to carry a date, so that Frisket is clear to see and to hear (D15, D16, D17).

### Editor marks (2026-09-25, decision 59)

102. As a user, I want to select a mark I already drew and move, resize, delete or restyle it, so that I fix a mark instead of undoing everything after it.
103. As a user, I want tapered arrows, curved arrows that I bend with a handle, double arrows and plain lines, so that I can point at things clearly.
104. As a user, I want to type a label directly on the image in a real font, choose its size and a Standard, Outlined or Box style, and set its width with a handle, so that labels look right and read well.

## Implementation Decisions

### Architecture and boundaries

- Frisket is built fresh. Snapzy is a read-only reference for scenarios, edge cases, and bug fixes (ADR 0001). The scrolling stitcher is Frisket-owned code; the trial port was removed, and nothing from Snapzy ships (ADR 0001; `docs/ported-files.json` is empty).
- Core logic lives in a Swift package that builds without Xcode. The app target (Xcode 26.5 with its SDK pinned, decision 47; package tests also need Xcode's toolchain for Swift Testing) holds AppKit and SwiftUI adapters. Dependency direction: adapters depend on the core; lifecycle policy never depends on AppKit controllers, preference singletons, or concrete GRDB types.
- Dependency allowlist is GRDB only, linked statically. No Sparkle, WebP, networking, analytics, URL scheme, or App Intents in v1.
- Deployment target macOS 26. Development builds are native architecture only; release builds are universal and label the arm64 half "built and signed, never executed" until an Apple-silicon run exists. Nothing is distributed before that run.
- Bundle identifier `io.github.prateeksingh1092.frisket`; development builds use `.debug` and a separate storage root and permission identity. Every app-owned path derives from the bundle identifier. An identity scrub check fails if Snapzy's name or author appears outside licence headers and notices.

### Modules

- **Command layer:** the single entry point for every action (capture area, window, full screen, scrolling; dismiss; open editor; annotate; redact; crop; Done; Copy; Save; drag; delete; copy text; launch recovery). Menus, shortcuts, thumbnails, and the editor all issue commands. Commands take typed capture identifiers and explicit inputs and return UI-independent results, so App Intents can be added later without new plumbing.
- **Capture lifecycle coordinator (deep module):** owns every Pending capture and its transitions, revision identity, and the decision to finalize, deliver, or discard. Its interface reports commit outcomes and delivery outcomes separately; retries refer to the same finalized revision; duplicate and stale commands are rejected safely. It enforces a global budget for pending bytes (refusing new scrolling captures beyond it) and, on quit, waits only for commits the user has authorized.
- **Capture source:** ScreenCaptureKit only. Every capture uses a content filter that excludes Frisket's own app and the apps on the Capture exclusion list; there is no fallback that relies on window sharing flags. Shareable content is prefetched when a capture shortcut fires. Permission state is modelled explicitly: not asked, denied, granted, revoked while running, needs relaunch.
- **Selection overlay:** a crosshair on every display, device-pixel magnifier, Shift, Option, Space, and arrow modifiers, Esc handled by the overlay's key panel without Frisket being active, selection confined to the origin display, window highlight excluding Frisket's panels, clean cancel on display unplug. Overlays are hidden before pixels are taken.
- **Scrolling capture:** **Retired (decision 60).** Manual scrolling only. Frames are compared with the previous frame only; new rows are copied into fixed-size strips and frames are released promptly. The pending original is held as compressed strips in memory. The editor works on a tiled or downsampled proxy; rendering and PNG encoding proceed strip by strip. A v1 pixel cap is set only after the trial measures memory; reaching the cap or the memory budget stops the capture with a message.
- **Stitcher:** **Retired (decision 60).** A pure function from frame sequence to image, including static header and footer detection and alignment scoring. It reads frames from memory and writes no temporary files. Its Vision use is recorded in test results.
- **Document model and renderer:** the editor edits a document (base image, annotations, crop, Solid redactions). The renderer is a pure function from document to bitmap. Solid redaction is its own element type: a fixed colour at full opacity, no corner radius or stroke, drawn with a copy blend and no antialiasing, its rectangle snapped outward to whole output pixels after crop and scale, applied to the base layer before any pixel-sampling effect; sampling effects read the redacted composite.
- **Editor:** AppKit, no document architecture, no autosave, no window restoration, no disk image caches, no Live Text on the original. Close with edits asks Finalize (Return, default), Delete capture (destructive), Cancel (Esc). Sudden termination is disabled while editors are open; Quit presents the same choice per editor; an interrupted logout or restart discards unanswered captures. Pre-crop display frames are discarded right after cropping.
- **Thumbnail stack:** a non-activating panel on the capture display, over full-screen Spaces. A global "focus thumbnails" shortcut makes it key temporarily; arrows move between cards; single keys trigger copy, save, edit, Delete capture, and dismiss. Each card is a VoiceOver element with custom actions and an announcement on arrival. Auto-dismiss is configurable including never, and pauses under focus. The thumbnail is built from the in-memory image by downsampling and refreshed from the rendered revision after finalization. Every exit path has a defined outcome (see Further Notes).
- **History store:** GRDB over SQLite in WAL mode with full synchronous writes and full-fsync. Owned files are addressed only by capture identifier under one app-owned root, which uses a `.noindex` name and is excluded from backup. Rows store an integer primary key plus a unique capture identifier, root-relative locations, dimensions, and logical byte sizes; states are only `finalized` and `deleting`. No OCR text is stored in v1.
- **Commit protocol (file-first):** after an authorized finalization request, write the PNG to staging, full-fsync, atomically rename into place, fsync the directory, then insert one row in one transaction. Thumbnails are a disposable cache generated after commit. The finalizer writes a finalization record alongside the image. Nothing is written under the root before an authorized finalization request, and original pixels are never written.
- **Launch recovery sweep:** takes an exclusive lock first, empties staging, adopts a row-less image only if its finalization record validates (matching identifier and marker, and the image decodes at the recorded dimensions) and otherwise discards it, deletes rows whose image is missing (logging an error code), finishes interrupted deletions, removes row-less thumbnails, and reconciles recorded sizes with disk. Running it twice yields identical state.
- **Retention and quota:** usage is the recorded logical sizes of all app-owned files (images, thumbnails, recovery archives until exported or deleted) plus the database and its WAL and shared-memory files, re-measured at launch. A failed size read blocks the commit. Enforcement runs after each commit from indexed stored sizes, oldest first, with deterministic tie-breaking. A capture that alone exceeds the size limit is refused from History with a notice while delivery continues. Age eviction is deferred when the clock looks anomalous (earlier than the newest committed capture, or jumped past the last sweep by more than the retention window); future-dated captures are normalized once. Deletion marks `deleting` (hidden, still counted), unlinks files directly (never the Trash), then deletes the row. Quota eviction emits an event the UI shows as a one-time notice and a Settings line.
- **Migrations:** never erase the database in any configuration. Created with incremental auto-vacuum and secure delete. Shipped migrations are never edited; a database with unknown migrations is refused without writes. If the database can't open or migrate, History is disabled with a visible notice and a recovery option, and capture and delivery keep working.
- **Delivery adapters:** Clipboard writes image data only, restricted to this Mac and marked concealed for clipboard managers; it records the change count and replaces its own copy with the redacted result on finalization if unchanged; it never reads the general clipboard. File export writes PNG to `~/Pictures/Frisket` by default, copies and never moves, and Settings refuses an export folder inside the app-owned root and flags iCloud-synced folders. Drag uses file promises of the rendered revision with a copy-only operation; each staging file stays until the promise's write completion has returned and the drag session has ended, then is deleted and swept at launch.
- **Text recognition:** Vision runs only on the rendered revision; stale results are dropped. The notification says only "Copied N characters".
- **Shortcuts:** Carbon hot keys only; no event taps and no global mouse monitors while idle. Defaults are Command–Shift and a number (decision 55). When one of those bindings is still an enabled macOS screenshot shortcut, Frisket turns that symbolic hotkey off and remembers it for restore. Remapping validates against the system list and fails closed when it can't verify.
- **Settings and onboarding:** SwiftUI. Retention days and size limit, shortcuts, auto-dismiss, export folder, Capture exclusion list, eviction history line, third-party notices. Onboarding covers permission, what History keeps, and that Save keeps a permanent copy.
- **Diagnostics:** a logging interface that accepts only an event from a closed set, an error domain and code, and fields from a fixed allowed set; no free-text strings. System-log and assertion messages are static text. Local only, 7-day retention.
- **Signing and build:** a stable signing identity from Prateek's Xcode Personal Team (created when the first build needs it), hardened runtime, minimal entitlements written fresh, no debugging entitlement on the installed build, one fixed install path, and one signing path. No update feed or key. Packaging steps are documented; a packaging script is written only when a delivery need exists. Before the first commit: the project licence is MIT (decision 56, which amends decision 43), third-party notices (GRDB, copied skills, and Snapzy if the stitcher is ported), extended ignore rules, a staged-diff secret review.

## Testing Decisions

- **Remediation seams (decision 57).** Tests for stories 82–101 run at these interfaces:
  - `CaptureFlattening.flatten`, and `CaptureRenderer.preview(...).render(edits)` for preview parity;
  - `ScrollingCaptureSession.ingest` (**Retired (decision 60).**);
  - `WindowSelection(rows:)`;
  - the Thumbnail status from `thumbnails()`;
  - `HistoryStore.rows()`;
  - `deliver(.drag)`.

  The red loops on branch `diagnose/red-loops` are the first tests at these interfaces.
- A good test drives the app the way a user would and checks only observable results: command outcomes, public queries, bytes delivered to recording stand-ins, and files on disk. Tests never reach into private state, reflection, or timing internals.
- **Seam 1, the command layer over the Capture lifecycle coordinator:** tests issue commands against stand-ins for the clock, the screen pixel source (fixtures), the clipboard, the drag handoff, and text recognition, with a real file store and real SQLite in a temporary directory. This covers lifecycle transitions, every thumbnail exit path, editor close and quit choices, retention and quota (including an oversized capture and equal timestamps), clock anomalies, delivery retries and stale commands, the history-database failure mode, and OCR on the rendered result.
- **Redaction leak tests through seam 1:** fixtures place unique "canary" colours under each redaction; every output (clipboard, saved file, History image, drag file, thumbnail) is decoded in a fixed sRGB space, and every covered pixel must equal the fill with full opacity and no canary colour may appear anywhere. Cases cover 1x and 2x sources, fractional rectangles, crop, and an overlapping blur or magnifier.
- **Crash recovery through seam 1:** a closed list of named commit points. Tier 1 injects a fault at each point in process, rebuilds over the same directory, runs recovery twice, and asserts invariants and size totals matching disk. Tier 2 uses a small helper executable that kills itself at a chosen point; at least one case per point. A test fails if a commit point exists without a matching case.
- **Seam 2, the renderer:** pure pixel-exact tests of the Solid redaction rules and annotation rendering, including render-equivalence and frozen-snapshot cases.
- **Seam 3, the stitcher:** **Retired (decision 60).** Synthetic generated frame tests with byte-exact expectations; a few recorded real scroll sequences (no personal content, provenance documented) with sticky headers and fixed footers, asserting properties such as height within tolerance and no duplicated bands; a synthetic 5120×57,600 capture that must complete without truncation or downscaling with peak physical footprint under 2 GB.
- **Real Vision checks:** a small, tagged, local-only set pairing a positive case (canary text recognized when unredacted) with a negative case (absent once redacted), recording the OS build.
- **Static checks:** dependency allowlist, identity scrub, licence header and provenance consistency, no writes under the root before finalization, no free-text logging, planted-secret log test, no event taps or global monitors while idle.
- **Manual checklist (scripted, recorded):** each run records date, OS build, commit, architectures and code signature, display layout, and permission state, with no personal pixels. It uses a bundled test-pattern window at known coordinates and a script that checks output dimensions and marker pixels. Required cases: each Screen Recording state (not asked, denied, granted, revoked while running, after re-signing, needs relaunch); the built-in Retina display plus the external 1x display, including a display at negative coordinates and unplugging mid-selection; overlays over full-screen apps and across Space switches; Esc without activation; Full Keyboard Access and VoiceOver completing all thumbnail actions; each default shortcut triggering exactly one tool with system shortcuts enabled; a permission grant surviving two rebuilds.
- **Performance measurement (scripted, no Xcode):** idle CPU from process CPU time over 10 minutes, idle wakeups, memory footprint, and latency from app-logged monotonic timestamps; on AC power, thermally unthrottled, after cool-down, 20 runs, median and p95; confirm the low-power GPU. The 500 ms thumbnail target and other numbers stay placeholders until the macOS tool and Snapzy baselines are measured and Prateek ratifies targets.
- Tooling: every package test uses Swift Testing. A first probe must show `swift test` runs under the installed Command Line Tools; anything needing an app host is marked Xcode-only. Every verification report states the architecture and OS it ran on and that arm64 was not executed.
- Prior art: Snapzy's test scenarios are reference only; its stitcher deterministic tests and image factory are ported only with the stitcher. Its tests that protect persisted originals, blur redaction, or clipboard file locations are inverted, not ported.

## Out of Scope

- Screen or GIF recording, video, and webcam.
- Cloud storage, uploads, hosted sharing links, accounts, and any network feature.
- Auto-scroll and anything requiring Accessibility or Input Monitoring permission.
- Re-editing History items, and "export all history".
- Persisting OCR text or searching History by text.
- URL schemes, App Intents, Shortcuts actions, and plug-ins (the command layer keeps the door open).
- Taking over every macOS shortcut. Decision 55 takes over only the screenshot number row (⇧⌘3/4/5/6 and their Control variants).
- Capturing windows on other Spaces or minimized windows; selections spanning displays.
- Blur or pixelation as a redaction method.
- Localization beyond English.
- Honouring Increase Contrast and Reduce Transparency, and colour-blind-safe default palettes (proposed, not adopted; may return).
- Distribution beyond this Mac, notarization, an updater, and the paid Apple Developer Program.
- Apple-silicon runtime verification (no such Mac yet).

## Further Notes

- **Stitcher trial (before the scrolling-capture work):** **Retired (decision 60).** Extract Snapzy's stitcher into a scratch package, convert its tests to Swift Testing, and check that it compiles alone, passes on this Intel Mac, and completes the synthetic 5120×57,600 capture under 2 GB after moving to strip storage. Port it only if that costs less than a fresh implementation; otherwise write it fresh against the same tests. The trial involves builds and needs Prateek's approval when scheduled.
- **Prerequisites needing Prateek's approval at the time:** installing Xcode 26.6 (downloaded from Apple and signature-checked), creating the Personal Team signing identity, any build, app launch, screen capture, or clipboard use.
- **Exit outcomes (confirmed by Prateek as decision 44):** closing the editor without edits behaves like dismissing an unedited thumbnail (finalized to History, per decision 5). Thumbnail exits: timeout, swipe, close, overflow, and Esc dismiss (finalize to History); Delete capture discards; quit finalizes unedited thumbnails; display unplug moves the thumbnail to a remaining display; screen lock leaves it pending.
- The macOS periodic "bypassing the private window picker" alert can't be suppressed for this kind of app; Frisket must stay out of its way.
- Frisket can promise only removal from itself. Backups made before exclusion, APFS snapshots, receivers of delivered copies, and free-space remnants are outside its control; FileVault is recommended.
- Performance targets and the scrolling pixel cap become final only after measurement and Prateek's ratification.
