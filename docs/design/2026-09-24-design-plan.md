# Frisket design plan

| | |
| --- | --- |
| Date | 2026-09-24 |
| Status | Plan. Assessment and direction only. |
| Product | Frisket, menu-bar macOS screenshot app |
| Floor | macOS 26 |

This plan is an independent assessment of the current build. It does not revise `docs/design/2026-09-24-registration.md`, and the reviews below were instructed not to read that file.

## How this was assessed

Four specialist reviews read the current UI from source. Three of them also used public primary sources. Mobbin and Granola were not available: authentication was skipped, so this plan has no production-screen library and no meeting record.

| Role | Model | Result |
| --- | --- | --- |
| Visual hierarchy | Grok 4.7 extra high | Completed. [Visual hierarchy](67ce9c3d-210f-4d08-9cf8-6f4fb6eb7433) |
| Capture interaction | Grok 4.7 extra high | Completed. [Capture interaction](ebd875c5-dbe8-4760-bf35-a14d8b95797b) |
| Accessibility | Grok 4.7 extra high | Completed. [Accessibility](0154b4fb-cc37-438b-bede-609cbf59736a) |
| macOS 26 materials | Grok 4.7 extra high | Completed after an aborted first attempt. [Materials](dd4a082e-d7a9-4465-a91e-abbd2fb593de) |

Earlier attempts at the visual and interaction reviews on other models stopped at the included-usage limit and were rerun on Grok 4.7 extra high.

Accepted product decisions in `.scratch/screenshot-mvp/decisions.md` stay in force. Decision 54 already says design forks are not left open for a later pick. This plan records one direction. It does not reopen capture behaviour, retention, the solid-redaction pixel contract, shortcuts, or local-only storage.

## What lags

The capture loop is complete. The interface around it was built to make that loop true. Chrome is louder than the cut.

A person meets, on the surfaces they use most:

- A full-screen dim whose useful mark is the hole, then a keyboard manual painted on the wallpaper (`SelectionOverlay.swift`, `WindowSelectionOverlay.swift`).
- A floating card whose picture sits inside a material and under two rows of titled buttons (`ThumbnailPanel.swift`).
- An editor whose document is quiet and whose shelf is a harness of word buttons, mixed bezels, and an essay hint (`EditorWindow.swift`, `EditorTool.swift`).
- A scrolling session that opens a titled utility window on the page being scrolled (`ManualScrollingCapture.swift`).
- Sheets and Settings that repeat one stack: headline, paragraph, equal buttons (`OnboardingPanel.swift`, `PermissionRecoveryPanel.swift`, `AboutPanel.swift`, `HistoryWindow.swift`).

There is no shared visual system. Each surface invented its own material, type size, and button weight. The captured image is the product, and the interface competes with it.

## Specialist findings

### Visual hierarchy

The unfinished look is equal-weight verbs and written instructions on top of a mask that already works.

Strongest reasons, in the critic’s order:

1. The editor reads as a test harness on a real document. `.menu` material, 4 pt spacing, `.rounded` for Solid redaction and `.push` for the rest, full tool titles, a Label field that is always present, an 11 pt hint that truncates, and Undo, Close Without Changes, Copy, Save, Keep in History, and the drag well at one weight.
2. Selection and window pick paint a developer HUD on the dim. The cut and the size badge are the considered marks. The middle-dot sentence is leftover.
3. The thumbnail is a verb dashboard. The image is 248×132 inside a 288 pt card. The rest is buttons and a standing instruction.
4. The scrolling HUD is an absolute-frame sketch: titled 280×250 panel, 11 pt status, two equal rounded buttons.
5. Secondary windows share one weight. History restates its title and adds “There is no editor.” Onboarding is five equal paragraphs. Permission stacks three actions. Shortcut rows are headlines.

Keep structurally: the grouped Settings form, system alerts, and the editor canvas on `underPageBackgroundColor` with no frame and no decorative shadow. The selection hole and the size badge stay. The status item stays a template menu-bar symbol and a standard menu.

Daily-use rank, highest first: selection, thumbnail, window pick, editor, scrolling HUD, History, Settings, onboarding, permission, About, status item.

### Capture interaction

The loop matches the accepted behaviour and narrates it at every step. The frequent path is select, glance, then copy, drag, or wait. That path is slower to scan than the macOS screenshot tool, CleanShot’s after-capture overlay, or Shottr’s keyboard density.

Compared with public sources:

- [Apple’s screenshot help](https://support.apple.com/guide/mac-help/take-a-screenshot-mh26782/mac) describes a floating thumbnail for a few seconds. Swipe saves and dismisses, drag drops the picture, click marks it up. No button row and no caption. Frisket already has that skeleton, then labels every implication.
- [CleanShot’s screenshots page](https://cleanshot.com/screenshots) sells the after-moment as an image ready to copy, save, or drop. Annotation and solid redaction happen before the image leaves the Mac. The same page also sells backgrounds, brand presets, pin, cloud links, and an editable CleanShot file.
- [Shottr](https://shottr.cc/) is a measurement instrument: ruler, color sample, zoom keys, and a wide tool shelf. Frisket already has a subset of its selection grammar and hides that grammar in a sentence.

Design problems, distinct from specified behaviour: on-canvas manuals, titled thumbnail buttons, idle History captions, titled editor tools, policy names on Done and Close, and a titled scrolling window. Specified behaviour that stays: the six shortcuts, dismiss-to-History, Delete capture, editor on demand, manual scrolling, no History re-edit, and the existing keys.

Take the pace of “the picture is ready to throw.” Leave CleanShot’s share, pin, frames, and cloud. Leave Shottr’s ruler, color picker, and editor-first default.

### Accessibility

Decision 24 is already in the chrome and must survive a visual pass: English; full keyboard on capture and the thumbnail, including keypad Enter; VoiceOver labels on controls; canvas contents exempt; thumbnail custom actions that do not depend on hover.

Defects in the current visuals:

| Item | Severity | Where |
| --- | --- | --- |
| Scrolling HUD cannot become the key window, so Done and Cancel have no keyboard path | Blocker | `ManualScrollingCapture.swift` |
| Selection and window hints are white type on a thin veil, so they disappear on light wallpaper | Major | `SelectionOverlay.swift`, `WindowSelectionOverlay.swift` |
| Editor guides are `systemRed` alone | Major as a visual defect. A color-safe ink set is not accepted policy (UX-8 was not adopted) | `EditorWindow.swift` |
| Menu-bar symbol drops `isTemplate` and can show a colored warning | Major | `FrisketApp.swift` |
| The 5×7 bitmap face drops lowercase, punctuation, and any word that is not A–Z or a digit. The live Text guide draws the real string | Major | `AnnotationFont.swift`, `EditorWindow.swift` |
| The editor hint truncates the line that says blur and magnify do not conceal | Major | `EditorWindow.swift` |
| Thumbnail failure captions are not announced | Major | `ThumbnailPanel.swift` |
| Copy’s focus outline is a rounded rect drawn on a system button | Minor. A visible outline stays required | `ThumbnailPanel.swift` |

Reduce Motion, Reduce Transparency, and Increase Contrast are design guidance. They are not current product policy.

### macOS 26 materials

Read against the local SDK header `NSGlassEffectView.h`, the [Materials HIG](https://developer.apple.com/design/human-interface-guidelines/materials), [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [WWDC25 session 310](https://developer.apple.com/videos/play/wwdc2025/310/), and [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views).

The HIG sentences this plan uses:

> Liquid Glass forms a distinct functional layer for controls and navigation elements — like tab bars and sidebars — that floats above the content layer.

> Don’t use Liquid Glass in the content layer.

> If you apply Liquid Glass effects to a custom control, do so sparingly. Limit these effects to the most important functional elements in your app.

Current misuse:

- The thumbnail puts the capture inside `.regularMaterial`. The image is content. The material samples it.
- The editor shelf is an `NSVisualEffectView` of material `.menu` placed behind the buttons. `.menu` is the wrong semantic material, and a sibling effect behind controls is the pattern WWDC 310 tells AppKit apps to stop using.
- Selection and window overlays correctly use cheap fills, not glass. They must stay that way. Glass samples a region larger than the view, which is both a secret-sampling problem and a cost on the drag path.

Stock titled windows already adopt Liquid Glass: History, Settings, onboarding, About, permission, alerts, and the menu. Custom `NSGlassEffectView` is justified in one place: the borderless thumbnail, around its controls only, with the image outside `contentView`. The editor should use a stock toolbar or stock buttons rather than a second custom glass shelf.

Hard rule: captured pixels, the selection hole, and solid-redaction black are not materials. Redaction stays opaque black. Glass, blur, and tint are not concealment.

## Where the reviews disagree

**Annotation face.** The visual review treats the 5×7 glyphs as the right quiet voice inside the pixels. The accessibility review treats them as a defect: the person types a word, the guide shows that word, and the finalized capture stores block capitals. This plan sides with the accessibility finding on the alphabet, and with the visual finding on the voice. Annotation type stays inside the image, at one modest size, in the system face. It is not a display font, and it is not a toy bitmap. The guide and the finalized pixels show the same string.

**How much custom glass.** A looser reading would wrap the editor shelf and the scrolling HUD in `NSGlassEffectView` because they float. The materials review is stricter, and this plan follows it. Stock controls already become Liquid Glass on macOS 26. Custom glass is reserved for the thumbnail’s control cluster, because that panel has no title bar to host them. Everywhere else, remove the custom material and let the system controls show.

**Color-safe inks.** The accessibility review wants a second cue besides red. UX-8 was not adopted, so this plan does not introduce a palette policy. Guides keep weight and a plate where the desktop is arbitrary. Red may remain the default annotation ink. Solid redaction stays black and stays visually separate from that ink.

## Direction

Frisket is a cut mask. The loud marks are the selection hole, the window cut, and opaque black redaction. Captured pixels stay opaque evidence. Chrome is quiet macOS 26, and it speaks only when a verb or a failure needs to be seen.

Five rules:

1. **The mask is the product.** The hole, the window highlight, and solid black are the only loud marks.
2. **Pixels are content.** No glass, tint, or material samples a capture, a live preview, or a redaction.
3. **One verb at a time.** Copy on a fresh thumbnail. Conceal while editing. Done while scrolling. Continue when permission blocks capture.
4. **Instructions leave the glass.** Keyboard maps stay available to VoiceOver and in Settings or Help. They are not painted on the desktop or repeated as idle captions.
5. **System chrome stays system.** Grouped Settings, alerts, menus, and titled windows keep their platform form. Type is the system font. Measurement digits are monospaced so the size badge does not jitter.

## Surface plan

### Selection and window pick

Keep the dim, the clear hole, the crosshair, the modifier and arrow grammar, mouse-up to capture, Return and keypad Enter, and Esc. Keep the size badge, and draw it as an opaque chip so it does not depend on the wallpaper.

Remove the corner manual from both overlays. The VoiceOver label becomes a short name (“Select capture area”, “Select a window”). The full key sentence moves to help. While a modifier is held, the badge may gain one quiet word (locked, from centre, move). At rest, the badge is only the measurement.

Window highlight stops tinting the window interior. The interior is a hole, with the same stroke language as area selection. Both overlays use one veil strength so the two modes are one instrument.

No glass and no animation on the drag path.

### Thumbnail

The card is the picture. Drag still starts on the image. The image is an opaque sibling of the controls, not a child of the material.

Controls become one compact strip: Copy remains the primary and the focused control. Save, Edit, Copy Text, and Delete stay, as symbols with the current VoiceOver labels and the current keys. Dismiss is Esc, swipe, timeout, overflow, or the window close, including ⌘W. It is not a peer button, and the idle sentence about History goes away. “Kept in History” remains the short confirmation, spoken as it is today.

The status line appears when something failed. Those sentences are also announced.

If the card needs a material, it is regular glass around the controls only. Reduce Transparency and Increase Contrast, when enabled, replace that glass with an opaque system fill. The image never enters the sampler.

The visible Copy outline stays. It uses the system focus ring on the system button.

### Editor

The canvas stays the under-page ground, unframed, nearest-neighbor. Guides are not baked until mouse-up.

The shelf becomes one tool strip of symbols, with the existing keys and the existing accessibility labels. Solid redaction stays in its own group so it is not a drawing tool that happens to be red. The Label field is enabled only for Text. The hint is one short line for the active tool and does not truncate the conceal warning. Blur and magnify still say, in VoiceOver, that they do not hide pixels.

Actions read as document actions: Undo, Copy, Save, Done, and the drag well. Esc and the close box still finalize a clean editor to History. A dirty close still uses the system alert: Finalize, Delete capture, Cancel.

Live guides: redaction is a black stroke with a light edge, unfilled, so it cannot be mistaken for a tinted annotation. Crop keeps the dim outside the kept rect. Arrow, shape, and text use the active ink at a visible weight. Blur and magnify use the label color, not the annotation ink.

The shelf uses stock toolbar or stock button glass. It does not use a `.menu` backdrop, and it does not get its own `NSGlassEffectView`.

### Scrolling HUD

A short floating companion on the capture display: live preview, Done, Cancel. No title, no idle paragraph. Limit and failure sentences stay verbatim when the stitcher emits them.

The preview is opaque and outside any glass. Done and Cancel are stock buttons. After selection hides, the panel can take Return, keypad Enter, and Esc without activating the app and without an event monitor that steals scrolling from the page.

### History, Settings, onboarding, permission, About

History drops the in-content title and the “no editor” sentence. Rows stay a thumbnail, measurement, and date. Copy, Save, and Delete stay words, because this is a document window, not a capture overlay.

Settings stays one grouped form. Section essays become one line each. Apply stays an explicit button with a short visible title and the current specific accessibility label. Recording a shortcut still shows a clear selected state that is not color alone.

Onboarding keeps the tested facts, including the Screen Recording permission, the 30-day or 1 GB limit, Save as a permanent copy, the privacy limit, FileVault, and Command–Shift–4 and Command–Shift–3. Each fact is a row with a template symbol. Continue stays the primary action.

Permission keeps the same four actions. One of them is primary. The window has a label and an announcement. Explanations stay specific and get shorter only where the next action is already named by the button.

About stays a version and the bundled notices. No capture, path, or diagnostic payload.

### Status item

The menu-bar glyph stays a template symbol in both states: the viewfinder when Screen Recording is granted, an untinted triangle when it is missing. The spoken label and tooltip already carry the permission state. Menu rows may gain template symbols. Key equivalents stay as they are, including the main-menu History chord.

## Sequence

Work in this order so the daily loop changes first and later surfaces reuse the same rules. Each step is a visual and interaction change. None of them reopen the capture, retention, or redaction contracts.

1. **Selection and window pick.** One veil, one hole, opaque badge, manuals off the glass, VoiceOver labels shortened with the full keys kept in help.
2. **Thumbnail.** Image outside the material, one control strip, dismiss no longer a peer button, failure lines announced.
3. **Editor shelf.** Symbol tools, one hint, Done, stock controls, guides that separate redaction from ink.
4. **Scrolling HUD.** Quiet panel that can take Done and Cancel from the keyboard.
5. **Annotation face.** System-font words inside the image, guide and finalized pixels in agreement. This is the only step that changes baked pixels, and it waits until the shelf no longer teaches a bitmap alphabet.
6. **History and the sheets.** Quieter copy and row metrics. Settings, onboarding, permission, and About share type and spacing. Status item template fix can land with this step; it is small and does not depend on the others.

Steps 1–4 can be reviewed against the synthetic test pattern. Step 5 needs renderer tests. Step 6 needs the existing onboarding assertions to keep their required phrases.

## Out of scope

Recording, pin, cloud, accounts, share links, frames, gradients, device bezels, brand presets, a freeform pen, stickers, a screen ruler, a color picker, History re-edit, and any export format other than PNG.

A Dock icon is a separate artwork task. It is not part of making the capture loop quiet.

Bundled fonts, a Frisket palette, and glass on the selection or on captured pixels are out.

## Sources

- Current UI: `Frisket/ThumbnailPanel.swift`, `EditorWindow.swift`, `EditorTool.swift`, `HistoryWindow.swift`, `OnboardingPanel.swift`, `AboutPanel.swift`, `PermissionRecoveryPanel.swift`, `ExportSettings.swift`, `FrisketApp.swift`, `Frisket/Adapters/SelectionOverlay.swift`, `SelectionSizeBadge.swift`, `WindowSelectionOverlay.swift`, `ManualScrollingCapture.swift`, `Sources/FrisketCore/AnnotationFont.swift`, `OnboardingContent.swift`.
- Product constraints: `CONTEXT.md`, `.scratch/screenshot-mvp/decisions.md` (decisions 4, 5, 24, 28, 32, 44, 54, 55).
- Prior accessibility gap, not adopted: UX-8 in `.scratch/red-team/round1/ux.md`.
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [WWDC25 session 310](https://developer.apple.com/videos/play/wwdc2025/310/)
- [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview) and the macOS 26 SDK header `NSGlassEffectView.h` on this Mac
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Take a screenshot on Mac](https://support.apple.com/guide/mac-help/take-a-screenshot-mh26782/mac)
- [CleanShot screenshots](https://cleanshot.com/screenshots)
- [Shottr](https://shottr.cc/)
