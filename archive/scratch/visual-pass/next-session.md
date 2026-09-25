# Claude session brief: launch Frisket and beta-test the visual route

You are starting with zero chat context. This file is the job. The owner is Prateek. The app is Frisket, a menu-bar macOS screenshot tool. The repo is `/Users/16intelmac/Documents/Claude/Projects/screenshot-app`. Remote: `https://github.com/prateeksingh1092/screenshot-app.git`. This Mac is a 2019 16-inch Intel MacBook Pro (`uname -m` is `x86_64`). Floor is macOS 26. Xcode is `/Applications/Xcode.app` (26.5). `xcode-select -p` currently returns that Xcode. Set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` on every build and test command anyway.

Your job is to launch the app and use every small control the way several different people would, then write what each person would actually notice. A control that responds is only the first angle. Also record the words, the key, where focus lands, what VoiceOver would hear, what a failure looks like, whether the captured picture stays the content, and whether a mark can be confused with solid black redaction.

## Read this first, in this order

1. This file.
2. `CONTEXT.md` for the words Capture, Scrolling capture, Annotation, Solid redaction, Pending capture, Finalized capture, History, Export.
3. `.scratch/screenshot-mvp/decisions.md`. Decision 54 means you pick the best-evidenced option and record it. Decision 55 is the shortcut row below.
4. `.scratch/visual-pass/map.md` and `.scratch/visual-pass/issues/01` through `04`. Those four tickets are the locked visual route. `docs/design/2026-09-24-registration.md` and `docs/design/2026-09-24-design-plan.md` are the two source plans. Where they disagree, the tickets win.
5. `docs/app-build.md` for the exact build, sign, and install commands.
6. `docs/manual-checks/` as the catalogue of every operator-facing behavior. Walk those files as the beta script. `08-first-launch.md` has the synthetic-pattern launch sequence.

## Who already did what

Grok, in the terminal session that wrote this file, implemented the visual route in the working tree and compiled it unsigned. Cursor, on 2026-09-24, ran an independent design assessment and wrote `docs/design/2026-09-24-design-plan.md`. That assessment used four Grok 4.7 extra-high reviews (visual hierarchy, capture interaction, accessibility, macOS 26 materials). It was instructed to leave `docs/design/2026-09-24-registration.md` unread. Earlier Cursor attempts on other models stopped at the included-usage limit and were rerun on Grok 4.7 extra high. Prateek later said the Cursor side of that assessment was also Grok 4.7 extra high, alongside Claude Opus 5.5 at max effort. Cursor did not implement the UI. `docs/agents/cursor-workflow.md` still says full Xcode is absent. That sentence is stale. Xcode 26.5 is installed.

Registration (`docs/design/2026-09-24-registration.md`) was committed on `main` as `2bb6ff7`. It is a plan. Its ending list of ten changes was a proposed build order, not GitHub pull requests.

## Locked visual decisions

- The loud marks are the selection hole, the window cut, and opaque black solid redaction (`RGBAPixel` 0,0,0,255, square, no opacity).
- Custom Liquid Glass is one regular `NSGlassEffectView` around the thumbnail controls and status only. The picture is an opaque sibling and does not overlap the glass. The editor uses the stock toolbar. The scrolling panel uses stock buttons. The selection badge and notices are solid fills. Reduce Transparency stays with the system material.
- Annotation ink is one color, today's signal red `RGBAPixel(255, 59, 48, 255)`, plus a 1-output-pixel white plate `RGBAPixel(255, 255, 255, 255)`. The plate is a constant write after the second redaction fill. It skips pixels inside a solid redaction. There is no swatch row and no color picker.
- Keyboard manuals live in `accessibilityHelp` on the overlay. The spoken names are "Select capture area" and "Select a window". The full keys, including keypad Enter and Shift-arrow, stay in that help string.
- Shortcuts stay ⌘⇧1 History, ⌘⇧2 focus latest thumbnail, ⌘⇧3 full screen, ⌘⇧4 area, ⌘⇧5 window, ⌘⇧6 scrolling.
- Onboarding still contains the phrases the tests lock: "Screen Recording permission", "30 days or 1 GB, whichever limit is reached first", "Save keeps a permanent copy", "only from itself, not from apps, devices, or backups", "FileVault is recommended", "Command–Shift–4", "Command–Shift–3". Scrolling limit sentences stay verbatim. See `ScrollingCaptureCommandsTests` and `OnboardingAndAboutTests`.

## What the code already contains

Implemented in the dirty tree that this commit includes:

- Area and window overlays: 40% veil, clear hole, black outer stroke then white inner stroke, 12 pt corner ticks, opaque measurement badge. Shift / Option / Space add one word on the area badge: locked, from centre, move. The other displays show a solid chip: "Selection stays on the display where it started. Esc cancels."
- Thumbnail: picture outside the glass, Copy as the word button, Save / Edit / Copy Text / Delete as symbols, dismiss by Esc, swipe, or ⌘W. Failure lines are announced. The idle History sentence is gone.
- Editor: menu-material shelf removed. Symbol buttons on `NSToolbar` (`unifiedCompact`). Letter keys R C A S T B M select tools when the label field is not the field editor. Hint wraps in the content view. Redaction guide is unfilled black with a white edge. Arrow and shape guides are red with a white plate. Blur and magnify use the label color. Drag well corner radius is cleared on the editor instance only.
- Scrolling panel: borderless `ScrollingKeyPanel` with `canBecomeKey`, `becomesKeyOnlyIfNeeded = false`, `makeKey()` after show. Return, keypad Enter, and Escape hit Done and Cancel. Preview sits on an opaque under-page fill. Notice strings are unchanged.
- Renderer: `DocumentRenderer.plate` and `DocumentRenderer.outputCount(points:scale:)` with no floor of 1. Plate tests are in `textUsesTheClosedBitmapFont`. Redaction neighbours stay black in `annotationsDrawAboveRedactionsWithoutClearingNeighbourFill` and `annotationsAppearOnEveryOutputWithoutWeakeningRedactions`.
- History window drops the in-content title and the "There is no editor." sentence. Window title remains "Frisket History".
- Menu-bar image stays a template symbol: `camera.viewfinder` when Screen Recording is granted, `exclamationmark.triangle` when it is missing.

Still open, and in scope for you if the running app shows the old behavior:

- Annotation text inside the image is still the 5×7 bitmap in `Sources/FrisketCore/AnnotationFont.swift`. The live guide draws the typed string with the system font. The saved pixels still store the bitmap. The agreed seam is: the app target rasterizes `NSFont.systemFont` at 18 document points into a binary mask, FrisketCore stamps that mask with `outputCount`, and FrisketCore stays free of AppKit. Guide and saved image show the same string.
- Settings essays, onboarding rows, the permission sheet's primary action, and About have not had the quieter pass. Keep the locked phrases above while you do that pass.

## Compile that already passed

On 2026-09-24 the unsigned Development build succeeded. Product:

`.build/DerivedData/Build/Products/Development/Frisket.app`

Command, from the repo root:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
xcodebuild -project Frisket.xcodeproj -scheme Frisket \
  -configuration Development -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO build
```

That product is unsigned. The same session also passed `DocumentRendererTests` (20 tests) and `EditorRedactionCommandsTests` (25 tests) through:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --disable-sandbox --disable-keychain --disable-xctest \
  --cache-path .build/cache --scratch-path .build \
  --config-path .build/config --security-path .build/security \
  --filter DocumentRendererTests
```

Swap the filter for `EditorRedactionCommandsTests`. The full suite is `sh scripts/test-core.sh`. Optional heavy checks use `FRISKET_MEMORY_RUN=1` (`scripts/stitcher-memory-run.sh`) and `FRISKET_EDITOR_MEMORY_RUN=1` (`scripts/editor-memory-run.sh`). `scripts/first-run-record.sh` writes host metadata only.

## How to launch

The app you launch is `/Users/16intelmac/Applications/Frisket.app`. Debug bundle id `io.github.prateeksingh1092.frisket.debug`. History root `~/Library/Application Support/io.github.prateeksingh1092.frisket.debug/History.noindex`. Quit that app before replacing the bundle. Sign through Xcode with the existing Apple Development identity, team `9M43Q952NK`, then `ditto` the Development product onto that path. The full sign, copy, and `codesign --verify` commands are in `docs/app-build.md` under "One signing and install path". After install, confirm identifier `io.github.prateeksingh1092.frisket.debug`, TeamIdentifier `9M43Q952NK`, and hardened runtime. Leave the existing Screen Recording grant in place. A new signed bundle with that same identifier keeps the grant.

Then:

```sh
open /Users/16intelmac/Applications/Frisket.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -target x86_64-apple-macos26.0 \
  -module-cache-path "$PWD/.build/module-cache" \
  Tools/FrisketTestPattern.swift -o .build/FrisketTestPattern
.build/FrisketTestPattern --show
```

Pattern modes: `--show`, `--show-all`, `--show-full-screen`, `--full-screen`, `--show-window`, `--show-scroll`. Verifiers: `--verify FILE 1|2`, `--verify-full FILE WIDTH HEIGHT 1|2`, `--verify-redacted FILE 1|2`. The pattern is a 320×180 point block, red/green over blue/white, plus a black marker, centered on the display. Escape closes the pattern. Put the pointer on the pattern before ⌘⇧4.

This Intel display's main frame was 1792×1120 points. A 320×180 capture at scale 1 has passed the verifier before.

## How to drive it

Carbon shortcuts ignore System Events keystrokes. Post `CGEvent` keyboard events to the HID tap. Key codes: 18–23 are the digits 1–6, 36 is Return, 76 is keypad Enter, 53 is Escape. SwiftUI thumbnail buttons are often invisible to System Events as buttons. Use `AXUIElementPerformAction(kAXPress)`. Area and window selectors are borderless accessibility windows. Thumbnail and History drags start only after the pointer moves about 3 points. `DragStart.track` in `Frisket/Adapters/FilePromiseDragAdapter.swift` activates the app at that moment.

Menu bar icon is a template `camera.viewfinder`. The status menu is the way in when a shortcut is held by CleanShot. Quit CleanShot when you need the ⌘⇧ number row.

## Beta script

Act as four people, in order. Write one note per person under `.scratch/visual-pass/beta/`. Each note is a table: surface, what you did, what you saw, what you heard or would hear in VoiceOver, what failed or felt unfinished, file or pixel evidence.

1. **First-run person.** Launch. If Screen Recording is missing, use the recovery panel and System Settings, then reopen the installed path. Open onboarding and About. Read every sentence aloud in the note. Hit Continue. Open Settings and record one shortcut, then put the old shortcut back.
2. **Capture person.** With `--show` up, run ⌘⇧4, ⌘⇧5 (`--show-window`), ⌘⇧3 (`--verify-full`), and ⌘⇧6 (`--show-scroll`). On the area overlay, drag, Shift-lock, Option-from-centre, Space-move, arrows, Shift-arrows, Return, keypad Enter, Escape. Read the badge. On a second display, read the solid chip. Copy the thumbnail, Save it, Copy Text, Edit, Delete one capture, dismiss another with Esc and another with a horizontal swipe. Paste into the verifier.
3. **Editor person.** Solid redaction over the red quadrant, then `--verify-redacted`. Crop. Arrow. Rectangle. Text with lowercase and punctuation, and compare the guide with the saved PNG. Blur and Magnify, then confirm the redaction is still opaque black. Undo. Dirty close, and use Finalize, Delete capture, and Cancel once each. Copy, Save, and drag the edited image.
4. **History person.** ⌘⇧1. Copy, Save, Delete a row. Read the window for a repeated title. Open the menu and check the template icon in both permission states if you can reach the missing-permission state without wiping the grant. If you cannot reach it safely, say so and inspect `refreshPermissionIndicator()` in `Frisket/FrisketApp.swift` instead.

Angles on every row: hierarchy (is the picture louder than the buttons), material (does glass sample the picture), language (one job per string), keyboard (the key does the same thing as the click), failure (disconnect a destination or cancel a panel and read the sentence), redaction (black stays black and looks different from the red ink).

## Where the rest of the knowledge lives

Repo first. Then Grok's project memory, which this session actually used:

`/Users/16intelmac/.grok/memory-v2/workspaces/screenshot-app-ef9519ca/topics/`

Read `frisket.md`, `frisket-capture.md`, `frisket-editor.md`, `frisket-automation.md`, and `frisket-demo.md`. The generated index is `MEMORY.md` in that folder. Treat the topic files as the notes. Global topics are `/Users/16intelmac/.grok/memory-v2/global/topics/`. A locked note there says the older tree `~/.grok/memory/` is the main Grok memory. This project's visual-pass facts from 2026-09-24 were written into the memory-v2 workspace topics and into the repo. If a fact conflicts, the repo file and a live command win.

Research that fed the tickets, if you need the citations, is on local branches `research/liquid-glass-placement` (`docs/research/2026-09-24-liquid-glass-placement.md`) and `research/ux8-annotation-cue` (`docs/research/2026-09-24-ux8-annotation-cue.md`). They may exist only as worktree branches under `~/.grok/worktrees/projects-screenshot-app/`. `git branch -a` and `git show research/ux8-annotation-cue:docs/research/2026-09-24-ux8-annotation-cue.md` are the way to read them.

Cursor's project rules are `AGENTS.md`, `docs/agents/cursor-workflow.md`, and `.cursor/skills/matt-pocock/`. The implementation workflow is `docs/agents/implementation-workflow.md`. Codex CLI is `/Users/16intelmac/.local/bin/codex`. Cursor's agent CLI is `/Users/16intelmac/.local/bin/cursor-agent`. The bare `agent` command on this Mac resolves to Grok.

When a fact is missing, search the repo, then those topic files, then the research branches. The accepted product language is `CONTEXT.md`. The accepted product choices are `.scratch/screenshot-mvp/decisions.md`.
