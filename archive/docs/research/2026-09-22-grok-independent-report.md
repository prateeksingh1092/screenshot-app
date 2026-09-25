# Independent research report: a local macOS screenshot app

**Research date:** 22 September 2026. **Method:** public product pages, Apple Support, Apple Developer Documentation, and GitHub repository metadata. **Not done:** installing apps, capturing on this Mac, or verifying binary architectures with `lipo`. Undocumented preferences are out of scope. Dollar amounts are USD from the cited page.

The 2019 16-inch MacBook Pro (`MacBookPro16,1` / `MacBookPro16,4`) is on Apple’s macOS Tahoe 26 compatibility list, and Apple’s model page lists **macOS Tahoe 26 as its newest compatible system**. It is not on the macOS 27 Golden Gate MacBook Pro list. Any app that requires macOS 27, or ships an Apple-silicon-only binary, is unusable here even when marketing says “Mac.”

## Executive recommendation

Do not start by cloning CleanShot. The stated goal is avoiding CleanShot’s fee, and a full CleanShot-class app is a multi-year product: capture, annotation, destructive redaction, scrolling stitch, history, OCR, recording, and a video editor. CleanShot 5.0, released 1 September 2026, moved the paid app further into polished screen recording. That is the wrong first milestone.

**Adopt first, build only the gap that remains.**

1. Use the built-in Screenshot app, Markup, Preview, and Live Text for ordinary region, window, and full-screen captures. That path has no subscription and no extra binary.
2. On this Intel Mac, the strongest free binary to try next is **macshot** (`sw33tLie/macshot`): native Swift, GPLv3, menu-bar capture, annotations, redaction, scrolling, OCR, pin, and history. Its published release is one DMG, so the x86_64 slice was **not** verified here. Requirements say macOS 12.3 or later, which includes Intel Macs that can run that system.
3. If a small one-time payment is acceptable, **Shottr** is the closest maintained screenshot tool: free with upgrade prompts after 30 days, **$12** once for one person on up to five computers, commercial use requires that license. It has no screen recorder. The developer describes it as optimized for Apple silicon; an Intel-native build was not proven from the site.
4. Build a new app only if those options fail a workflow you actually use every day: fast capture to the clipboard, reliable baked-in redaction, editable annotations, and a local history, with no account and no telemetry. Keep version 1 to still images.

**Important surprises**

- CleanShot Basic is now **$35 once**, not the older $29 figure still repeated by reviews. It includes the full Mac app, including the 5.0 video editor, for one year of updates. Optional update renewal is **$19 per year**. The app keeps working after that year. Pro is **$10 per user per month, billed annually**, for unlimited cloud, branding, and team controls. The pricing page has a monthly toggle marked “Yearly −17%”; the exact monthly dollar amount did not render in the fetched page. TidBITS on 4 September 2026 reported $12 per month or $120 per year, which matches $10 × 12.
- Current CleanShot requires **macOS 13 or newer**. Cloud is optional. Screenshot OCR is documented as on-device. Cloud transcription is not: CleanShot’s subprocessor list names **RunPod** for audio from recordings uploaded to CleanShot Cloud.
- **Flameshot 14.0’s “Intel” DMG is not a trustworthy Intel download.** A 19 June 2026 GitHub issue reports that the Intel-labeled disk image is Apple-silicon-only (`bad CPU type` on an Intel Mac). Homebrew disabled the macOS cask on 1 September 2026 because it fails Gatekeeper.
- **Capso is not a permissive CleanShot substitute.** Its license is Business Source License 1.1. It forbids use as a commercial screen-capture product and names Apache 2.0 as the change license on **8 April 2029**.
- Several new “native CleanShot alternatives” are real Swift repositories, but popularity and README claims are not the same thing. `8tp/ScreenCap` has 4 stars and a 109 KB repository. `jaywcjlove/shotcat` is not a screenshot app; the screenshot project from that author is `jaywcjlove/scap`, which currently has **no GitHub license**.
- macOS 27 Golden Gate exists, and Rosetta for general Intel apps is documented as ending for ordinary apps in macOS 28. This Intel Mac’s ceiling is Tahoe 26. A new app should be a universal binary, with Tahoe as the tested Intel target, and should not depend on macOS 27-only APIs.

## 1. CleanShot capability inventory

**Coverage:** public pages fetched 22 September 2026: features, pricing, changelog, FAQ, URL-scheme API, cloud, and cloud subprocessors. No hands-on pass. Settings screenshots on the features page were not transcribed one control at a time, so this is not a complete inventory of every preference.

**Current release:** 5.0.1 on 18 September 2026 (small fixes). 5.0 on 1 September 2026 is the major release. A 4.8.11 build on the same day says it improves compatibility with macOS Golden Gate; treat 4.8 as a parallel compatibility line. The purchase FAQ says the current app needs macOS 13.0 or newer. Last versions called out for older systems: 4.8.10 Catalina, 4.8.4 Mojave, 4.1 Sierra and High Sierra. No Windows version.

**Price model:** Basic is a perpetual app license plus one year of updates and 1 GB of cloud. Pro is a subscription that keeps the app current and adds unlimited cloud and team features. There is no trial. There is a 30-day refund. A license includes a cloud account, and the FAQ says the account is not required to use the app. Setapp is an alternate distribution channel. Students get 30 percent off; PixelSnap 2 customers get 20 percent off.

### Capture

Documented modes: area, window, full screen, self-timer, scrolling capture, and previous area. All-in-One mode puts the modes on one shortcut, can lock aspect ratio and size, and remembers the last selection. Precision aids: crosshair, magnifier, and freeze-screen so a moving target can be framed. Window shots can be transparent, with shadow on or off, or placed on the desktop wallpaper, a color, or a custom image, with padding. Hold Shift while capturing to skip an automatic preset (changelog 4.8.4). Desktop icons can be hidden, and 4.7 also hides widgets. Full-screen app shots can auto-crop the notch. Retina images can be scaled to 1×. An option can convert shots to sRGB.

Scrolling capture is documented as working in any app, vertically and horizontally, with auto-scroll. The changelog shows this stayed buggy enough to need repeated algorithm fixes, so “works in every app” is a product claim, not a tested result.

### Annotation, redaction, crop, composite, backgrounds

Annotate is a native editor with crop (aspect lock and edge snap), arrows (four styles, including curved), line, rectangle, filled rectangle, ellipse, pencil with smoothing, highlighter with smart text-size detection, text (seven styles), counter, spotlight, rotate, and flip. The color picker can sample the screen and save colors.

Redaction is explicit: pixelate with randomization “for better security,” blur with secure and smooth options, and a blackout style added in 4.2. A Gaussian-blur option was added to pixelate in 4.1. These are the features to copy if redaction matters. A blur layer that can be toggled off later is not redaction.

Background tool: 20 built-in backgrounds, custom backgrounds, presets, padding, alignment, aspect ratio, and Auto Balance. Changelog 4.7 added 10 more backgrounds on top of the earlier set; the features page now says 20. Images can be dragged into Annotate and combined. `.cleanshot` project files keep annotations editable. Formats named in changelog and API include PNG, JPEG, WebP, and HEIC. The features page does not publish one exhaustive export list.

### Overlay, drag and drop, pin, history

The Quick Access Overlay appears after capture. It can copy, save, annotate, upload, show file info, restore a recently closed item, change size and screen position, auto-close, and accept drag-and-drop into other apps. Swipe gestures and keyboard shortcuts are documented (`⌘C`, `⌘S`, `⌘W`, `⌘U`, `⌘E` in the 4.1 notes).

Pinned shots float above other windows, with size, opacity, arrow-key placement, and a lock mode that clicks through to apps underneath.

History stores captures, can filter by type, restore, and delete. The features page says CleanShot can store up to one month. Double-click opens Annotate. External files opened in CleanShot can enter history.

### OCR and QR

Text recognition copies text from a selected screen area or from an image. The features page says recognition stays on the Mac, supports 30+ languages, and reads QR codes. Changelog 4.8 added automatic language detection, Arabic, WebP, and HEIC. Changelog 4.8.4 added more OCR languages on macOS Tahoe: Czech, Danish, Dutch, Indonesian, Malay, Norwegian, Polish, Romanian, Swedish, and Turkish. The FAQ says some OCR languages need the latest macOS. QR reading had a bug fix in 4.7.5, so it is not perfect.

### Shortcuts, automation, recording, Studio Mode

Nearly every behavior is described as configurable, including separate after-capture actions, file-name templates, and shortcuts. The URL scheme `cleanshot://` can open All-in-One, area, previous area, full screen, window, self-timer, scrolling capture, pin, record, OCR, annotate, clipboard annotate, desktop-icon visibility, the overlay, history, and settings. Actions such as `copy`, `save`, `annotate`, `upload`, and `pin` can be passed. Coordinates use the lower-left origin. The API can be disabled. A Raycast integration exists.

Recording, included in Basic and Pro: window, full screen, or a custom area; MP4 H.264; GIF; quality, frame rate, and resolution controls; microphone; computer audio; Do Not Disturb; show or hide the cursor; menu-bar timer; hide desktop clutter. Clicks can be highlighted. Keystrokes can be shown. A camera overlay has position, size, shape, and a full-screen mode. Recording can pause. A pre-5.0 editor could trim, change quality and resolution, and handle audio.

**5.0 Studio Mode** records into an editable project: smart zooms that follow the cursor, cursor smoothing, motion blur, backgrounds, post-record cursor and camera adjustments, trim, and hardware encoding. Export targets include landscape, square, and vertical. The pricing table marks this editor as included in both plans. This is the part that now overlaps Screen Studio. It is far outside a screenshot-first version 1.

### Cloud and team

Basic cloud: one-click upload, 1 GB, 4K, transcription, and comments. Pro adds unlimited storage, custom domain and branding, file access control, password protection, team management, SSO, and SCIM. Features copy also lists self-destruct links and an ISO 27001 claim. The February 2026 domain move put the dashboard on `cleanshot.com/cloud`; `cln.sh` short links remain. Push notifications for first view or comment arrived in 4.8.4. Fair-use policy applies to cloud plans. Transcription infrastructure is RunPod, so uploaded recording audio leaves the Mac.

Sources: [features](https://cleanshot.com/features), [pricing](https://cleanshot.com/pricing), [changelog](https://cleanshot.com/changelog), [FAQ](https://cleanshot.com/faq), [URL scheme](https://cleanshot.com/docs-api), [cloud](https://cleanshot.com/product/cloud), [subprocessors](https://cleanshot.com/cloud/subprocessors), [why updates expire](https://cleanshot.com/why-updates-expire).

## 2. Alternatives

**How these were chosen:** macOS screenshot workflow first, then price and whether data stays local, then whether an Intel Mac on Tahoe can run the current build, then whether the project was updated in 2025–2026. This is not a market-share ranking. Screen Studio and Kap are recording benchmarks only. Missing marketing text is not treated as proof that a feature is absent.

| App | What it is good at | Price, checked 22 Sep 2026 | Local vs cloud | Intel / OS | Maintenance |
| --- | --- | --- | --- | --- | --- |
| macOS Screenshot, Markup, Preview, Live Text | Region, window, full screen, timer, pointer, mic on recordings, floating thumbnail, Markup, Live Text in Preview and Quick Look | Included | Local files, default Desktop | This Mac, through Tahoe 26 | Apple |
| Shottr | Fast still capture, scrolling, annotation, backgrounds, OCR, QR, pin, pixel ruler, color picker, S3 upload | Free with prompts after 30 days. Basic **$12** once, one user, up to 5 Macs; commercial use needs a license. Friends Club **$30**. Upload requires activation | Local, plus optional S3. Update check, license check, and telemetry are documented | macOS 10.15+. “Optimized for Apple silicon.” Intel slice unverified | v1.9.2 on 17 Sep 2026, macOS 27 note |
| Snipaste | Window and UI-element snip, pixel control, color picker, history playback, and the distinctive paste-as-floating-window workflow | Free for personal use. 1.x stays free. From 2.0, business use needs a license: wiki says **99 CNY / $19.99**, major-version buyout, 3 devices | Local-first. Pro OCR and QR are paid | macOS version exists. Wiki edited 6 Jan 2026. Exact current macOS floor not re-read from a Mac download page | Closed source. Official site still documents the personal-free / business-paid split |
| Xnapper | Pretty backgrounds, balance, padding, shadow, radius, redaction, text copy, newer annotation controls | Free with watermark. Basic **$29.99** for 1 Mac and 1 year of updates; perpetual use of that version. Renewal later at 40% off. Personal $54.99 / 2 Macs, Standard $79.99 / 3 Macs. Team **$5 / device / month** annual | Local editor. Web cloud and share links added Dec 2024 | macOS 10.15+ on the pricing page. Intel-native slice unverified | macOS 1.18.1 on 28 Aug 2026 |
| Snagit | Repeatable documentation: capture, callouts, templates, sharing destinations, Windows and Mac | Subscription. Secondary sources quoting TechSmith say **$39 / year** individual. Perpetual new licenses ended with the 2025 generation | Account and hosted sharing are part of the product | TechSmith’s current requirements page: macOS Golden Gate 27, Tahoe 26, or Sequoia 15. Older branches cover older systems. No separate Intel CPU floor found for Snagit | 2026.3.3 cited by a 17 Sep 2026 secondary check. Confirm on the store before buying |
| Zight (formerly CloudApp) | Capture that becomes a link: annotate, scroll, GIF, record, then share | Free Share plan: screenshots, annotation, recordings up to 5 minutes, 15-second GIFs, last 50 items. Support article 8 Aug 2026: Create **$12.95 / month** or **$9.95 / month** annual, and warns the table may lag checkout | Account required. Library is in Zight’s cloud, not the Desktop | Mac, Windows, Chrome, iOS. Universal binary claimed by a download listing; not verified here | Active help center in Aug 2026 |
| Monosnap | Capture, markup, blur, GIF, upload, recordings | Free tier is personal / non-commercial, with limited storage and a 5-minute recording cap in the 2023 plan table. Paid non-commercial and commercial tiers exist. App Store and help-center prices disagree | Optional Monosnap storage and third-party drives | App Store listing requires a recent macOS (one store page said 14.6). Desktop 7.0 appeared in Jan 2026 listings | Maintained, but pricing pages are inconsistent |
| Flameshot | Cross-platform annotate-after-capture, strong on Linux and Windows | Free, GPLv3 | Local | v14.0 Intel DMG reported broken on Intel. Homebrew cask disabled 1 Sep 2026 for Gatekeeper | Repo active 17 Sep 2026. macOS build is the weak point |
| macshot | Closest free native CleanShot-shaped tool: annotate, redact, scroll, OCR, pin, history, GIF, editor | Free binary, GPLv3. Source reuse has copyleft duties | Local by default. Optional Drive, imgbb, and S3 | README: macOS 12.3+. Single DMG; x86_64 not verified. v4.2.1 fixed multi-monitor shift on macOS 26 | Code pushed 22 Sep 2026. Latest GitHub release is v4.2.1 on 10 Jul 2026, so release lags commits |
| eSearch | Cross-platform scroll, offline OCR, translate, pin, record | Free, GPLv3 | Local, with optional online translate and model downloads | **15.5.1 publishes `darwin-x64` and `darwin-arm64` disk images** | Release 13 Sep 2026 |
| Screen Studio | Auto zoom, cursor smoothing, motion blur, backgrounds for demos | Official current price **not captured** from `screen.studio` in this pass. 2026 secondary pages cluster around subscription-only, often $29 monthly or $108 yearly, and disagree about a retired lifetime offer. Treat price as unverified | Local editor plus share links on paid plans | Official guide: macOS 13.1+, M1 recommended, and Intel MacBook Pro 2018 or later is listed. A 2019 16-inch Mac meets that Intel line | Homebrew cask 3.7.5-4595, including an Intel Tahoe build, as of the formulae page |
| Kap | Simple open-source region recorder and GIF | Free, MIT | Local | v3.6.0 has an x64 disk image, dated 27 Oct 2022 | Last push 12 Nov 2024. Not a current base |

Native Screenshot details are from Apple’s Mac guide: Shift-Command-3, Shift-Command-4, Shift-Command-4 then Space, Shift-Command-5, Control to copy, timer and pointer options, thumbnail, Markup, and Preview. Live Text covers text already in an image. There is no system scrolling-stitch, no always-on-top pin tool, and no CleanShot-style history browser.

Shottr’s own FAQ is the price source, not the blog posts that still say $8. It also says the app contacts `shottr.cc` for version checks and sends telemetry. That matters if “local” means no network.

Snipaste’s lasting idea is paste-to-float: images, text, HTML, colors, and GIFs stay on top, with zoom, opacity, click-through, and groups. That is a different job from CleanShot’s overlay. Source code is not available to build on.

Xnapper is the background and framing tool. Its August 2026 notes improve annotation and pixelated redaction, so it is no longer only a beautifier, but it is still not a recorder-plus-history suite.

Zight and Monosnap solve sharing. Both put an account and a storage quota in the default path. They fight the cost and privacy constraint rather than satisfying it.

## 3. GitHub repositories

Lookup: GitHub REST API on 22 September 2026, plus release pages and READMEs where noted. Stars are a popularity count from that hour, not a quality score. “Source available” is not “you may copy this into a private app.”

| Repository | Stars | Release / activity | Stack and license | macOS and Intel | Role |
| --- | --- | --- | --- | --- | --- |
| [flameshot-org/flameshot](https://github.com/flameshot-org/flameshot) | 30,907 | Stable v14.0.0 published 19 Jun 2026. Tag v15.0.rc1 on 12 Sep 2026. Pushed 17 Sep 2026. Not archived | C++ / Qt, **GPL-3.0** | macOS DMGs exist. Intel-named 14.0 image reported as arm64-only in issue 4754. Homebrew disabled the cask 1 Sep 2026 | Mature annotation UX. Poor Intel binary today. GPL if distributed |
| [ShareX/ShareX](https://github.com/ShareX/ShareX) | 39,696 | Pushed 22 Sep 2026. Not archived | C#, **GPL-3.0** | Repository metadata does not present a macOS app. Windows reference only | Best workflow catalog: after-capture actions, destinations, OCR. Do not port the code |
| [CapSoftware/Cap](https://github.com/CapSoftware/Cap) | 22,634 | Pushed 22 Sep 2026. Not archived | Rust, TypeScript, Tauri. API license: **NOASSERTION** | macOS is a target; Intel slice not verified. Self-hosting is a server, not a menu-bar app | Recording and sharing product. License must be read before any reuse |
| [wulkano/Kap](https://github.com/wulkano/Kap) | 19,365 | v3.6.0 on 27 Oct 2022, with x64 and arm64 disk images. Pushed 12 Nov 2024. Not archived | TypeScript / Electron, **MIT** | Old x64 build exists. Unlikely to be a good Tahoe citizen | Historical GIF recorder. Do not start here |
| [lihaoyun6/QuickRecorder](https://github.com/lihaoyun6/QuickRecorder) | 8,664 | v1.6.9 on 11 Jun 2025, “fixed crash on Intel.” Pushed the same day. Not archived | Swift, ScreenCaptureKit, **AGPL-3.0** | Intel was an explicit fix, then development stopped. Release notes warned the free developer certificate expired 14 Jun 2025 | Recording implementation notes. Stale and AGPL |
| [xushengfeng/eSearch](https://github.com/xushengfeng/eSearch) | 7,200 | 15.5.1 on 13 Sep 2026, includes `darwin-x64`. Pushed 15 Sep 2026. Not archived | TypeScript / Electron, **GPL-3.0** | Intel disk image is published | Runnable Intel app today. Heavy runtime. Offline OCR is a headline feature; some models download on demand |
| [sw33tLie/macshot](https://github.com/sw33tLie/macshot) | 3,549 | Release v4.2.1 on 10 Jul 2026. Pushed 22 Sep 2026. Not archived | Swift / AppKit, **GPL-3.0** | macOS 12.3+. One DMG name; architecture unverified. macOS 26 multi-monitor fix is in that release | Strongest native app to try and to study |
| [amebalabs/TRex](https://github.com/amebalabs/TRex) | 1,912 | Stable v2.0.0 on 13 Feb 2026. Beta v2.0.1-beta.1 on 12 Jul 2026. Pushed 10 Aug 2026. Not archived | Swift, **MIT** | README: macOS 11+. Jul 2026 commit says universal arm64 + x86_64 binaries | OCR, QR, barcodes. Optional cloud LLM. Right library boundary for a later OCR pass |
| [lzhgus/Capso](https://github.com/lzhgus/Capso) | 1,349 | Pushed 3 Sep 2026. Not archived | Swift 6 / SwiftUI. **BUSL-1.1**, additional ban on a “Screen Capture Service,” Apache-2.0 change date 8 Apr 2029 | README in search results: macOS 15+. Intel not verified | Ideas only until 2029, and not for a competing capture product even then without reading the change terms |
| [Brkgng/ScrollSnap](https://github.com/Brkgng/ScrollSnap) | 926 | Pushed 2 Aug 2026. Latest release tag not fetched. Not archived | Swift, AppKit, ScreenCaptureKit, **MIT** | macOS scrolling specialist. Intel not separately verified | Best small repo for stitch behavior |
| [jaywcjlove/scap](https://github.com/jaywcjlove/scap) | 39 | Pushed 16 Sep 2026. Not archived | Swift / SwiftUI. **No license file reported by the API** | macOS annotation canvas. App Store listing exists; binary architecture unknown | Cannot legally reuse. Author’s `shotcat` name is an unrelated drama tool |
| [Amitdvl/SwiftShot](https://github.com/Amitdvl/SwiftShot) | 1 | Pushed 18 Sep 2026. Not archived | Swift / SwiftUI, **MIT**. README: macOS 14+, XcodeGen, Apple Development certificate | Claims vector annotations, window capture, OCR, pin, scrolling HUD, Shortcuts | Right shape, no track record. Read before copying |
| [8tp/ScreenCap](https://github.com/8tp/ScreenCap) | 4 | Pushed 11 Mar 2026. Repository size 109 KB. Not archived | Swift, **MIT** | README claims CleanShot parity. The tree size does not support that claim | Skip as a base |

`jaywcjlove/shotcat` was a bad lead: the public `shotcat` repository found under another owner is a storyboard and video workbench, not a Mac screenshot tool.

A Swift Forums post on 4 June 2026 describes **Mio** as SwiftUI plus ScreenCaptureKit, local-only, **macOS 26 or newer, and Apple silicon only**. The repository URL was not confirmed, and that platform line already excludes this Mac.

Greenshot was not given a full metadata pass. It remains a Windows screenshot project and is not a macOS adoption candidate.

### Shortlist

1. **macshot, to install and to read.** It already covers the screenshot workflow CleanShot is bought for, it is native, and it is active. GPLv3 means a private build for yourself is fine, and shipping a closed app that contains its code is not. Confirm the DMG actually contains `x86_64` before relying on it.
2. **ScrollSnap, to study and possibly adapt.** MIT, one job, ScreenCaptureKit, and recent commits. Scrolling stitch is the hardest capture feature; this is the smallest place to learn it.
3. **TRex, for the OCR boundary.** MIT, on-device Vision by default, universal-binary work in 2026, and a clear menu-bar capture-to-clipboard flow. Keep its optional LLM path out of a local-first build.
4. **SwiftShot, as an architecture sketch.** MIT and a vector annotation model match the editor you would want. One star means treat it as a reference, then rewrite.
5. **eSearch, as the Intel fallback binary.** The x64 disk image exists now. Use it if macshot’s binary is arm64-only. Do not fork it into a lightweight Mac utility; Electron and GPL are the wrong long-term base.
6. **Flameshot, for annotation interaction only.** The tool palette and launcher are the mature cross-platform reference. The current Mac binary is the wrong artifact for this computer.

Capso, ScreenCap, and scap lose on license or substance. Kap and QuickRecorder are recording apps, and both have gone quiet relative to Tahoe-era macOS. Cap is a shareable-recording product with an unverified license and a hosting story.

## 4. Recommendation for this project

### Build versus adopt

| Option | Cost | Fits this Intel Mac | What you give up |
| --- | --- | --- | --- |
| Built-in Screenshot + Markup + Live Text | No subscription, no extra install | Yes, through Tahoe | Scrolling stitch, pin, strong redaction, editable reopening, a real history |
| macshot binary, or eSearch x64 if macshot is not Intel | Free binary. GPL source if you modify and ship | macshot likely, unverified. eSearch x64 published | Trust and polish of a long-lived paid app. GPL if you later distribute a fork |
| Shottr Basic | $12 once, prompts until then. Commercial use must pay | macOS 10.15+ claimed. Silicon-optimized; Intel native unverified. Telemetry | Recording, GIF, CleanShot cloud. Not a private-source project |
| Snipaste personal edition | Free for personal use | Mac build exists; current Intel slice unverified | Business use of 2.x is paid. No source. Different interaction model |
| New Swift app | Your time. No paid API and no host in the default design | You can target Tahoe and ship a universal binary | Years of edge cases if scope copies CleanShot 5 |

Adoption is the better default. A new repository is justified after macshot, the built-in tools, and maybe Shottr have been used on the real multi-monitor setup and one of them fails.

### If you build: version 1, then later

**Version 1, still images only**

- Global shortcut, freeze the pixels, drag a region, copy to the clipboard, and save PNG.
- Window and full-screen capture, including the previous rectangle.
- A small thumbnail with copy, save, and annotate.
- Editable annotations stored as vectors: arrow, rectangle, text, counter, crop. Move, resize, undo.
- Redaction that is burned into the exported bitmap: pixelate, blur, and solid fill. The project file may keep the original only if export cannot reconstruct the hidden pixels.
- A local history folder you can reopen, with the annotation file beside the image.
- Configurable shortcuts and a save directory.
- Universal binary. Test on this Intel Mac on the newest system it supports, Tahoe 26, and on at least two displays with different scale factors.

**Later, in this order**

1. On-device OCR and QR through Vision, as a separate shortcut that copies text.
2. Pin-to-screen with click-through.
3. Backgrounds and presets.
4. Scrolling stitch, vertical first.
5. A `screenshot-app://` URL scheme.
6. GIF, then plain screen recording.
7. Studio-style zooms, camera, and transcripts stay out unless the product goal changes. They are a second application.

Cloud upload, accounts, and team admin stay off the default path. Optional S3 can wait until local export is boringly reliable.

### Stack proposal

This is a proposal, not an accepted decision.

- **Swift, with AppKit for the capture overlay and SwiftUI for settings.** The overlay needs precise windows, multi-display coordinates, and a global shortcut. A menu-bar web view is extra memory on a 2019 Intel laptop.
- **ScreenCaptureKit for pixels.** Apple introduced it in macOS 12.3. `SCScreenshotManager` single-frame capture is marked available on macOS 14. The rect-based and newer screenshot-configuration APIs show up as macOS 26 in the framework headers mirrored by the .NET bindings. This Mac can reach those 14.0 and, on Tahoe, 26.0 APIs. `CGWindowListCreateImage` is the legacy fallback and a poor long-term base.
- **Vision for OCR and barcodes,** on device. TRex’s 2.0 notes say table detection that uses the newer document API needs macOS 26, with a different fallback on older systems. Pin the deployment target to symbols you have checked, not to a blog summary.
- **AVFoundation later,** only if GIF or video survives the first release.
- **No paid recognition API and no required server.** A history directory in Application Support or a user-chosen folder is enough.
- **Permissions:** Apple’s ScreenCaptureKit sample says the first capture prompts for Screen Recording and the app must be restarted after approval. Scrolling and some global shortcuts also run into Accessibility or Input Monitoring in real apps. Zight’s own scrolling guide tells Mac App Store users to grant Accessibility. Budget for a permission screen that explains the restart.
- **License boundary:** read MIT code such as ScrollSnap, TRex, and SwiftShot. Do not copy GPL code from macshot, eSearch, or Flameshot into an app you might distribute under another license. Do not copy Capso under BUSL.

### Hardest engineering

- **Mixed-DPI multi-monitor coordinates.** Points, pixels, menu-bar height, and bottom-left versus top-left origins disagree. macshot’s July 2026 release was still fixing external displays that captured shifted on macOS 26. CleanShot’s changelog is full of the same class of bug, years in.
- **Do not capture your own UI.** Freeze first, or exclude the overlay. CleanShot 4.8.5 fixed hover states and OCR accidentally seeing its own All-in-One UI.
- **Redaction that survives export.** Draw the censor into the bitmap that is copied and saved. Randomized pixelate exists because a regular mosaic can sometimes be reversed. CleanShot added that randomization in 3.5.
- **Scrolling stitch.** It needs permission to scroll another app, stable timing, and overlap matching. Horizontal content, nested scroll views, and sticky headers break naive capture. CleanShot and Flameshot both treat this as ongoing work.
- **Editable documents versus flat images.** Store vectors, rasterize on the way out, and define whether the history copy still contains secrets under the redaction.
- **Permission and signing friction.** A local build needs an Apple Development certificate for a normal signed app. QuickRecorder’s expired free certificate is the cautionary tale. Distribution outside your own Mac adds notarization.

## 5. Gaps and questions that change scope

**Conflicts and holes**

- CleanShot’s monthly Pro price did not render as a number. Annual math and TidBITS agree on about $120 per year. Confirm at checkout if Pro is ever considered.
- Shottr third-party reviews still say $8 and “all features stay free.” The purchase page says $12, prompts after 30 days, and a commercial-use requirement. Future-update entitlement is not stated.
- Snagit’s Mac CPU floor is not stated on the requirements page used here. The OS floor for the 2026 branch is high: Sequoia, Tahoe, or Golden Gate. This Intel Mac on Tahoe can meet the OS line; a machine left on Sonoma cannot use that branch.
- Screen Studio’s official system guide lists Intel MacBook Pro 2018 or later. Its current price was not taken from the official pricing page, and secondary pages disagree.
- Monosnap’s help-center table is dated June 2023. App Store prices differ. Do not budget from the old table.
- macshot, Shottr, Xnapper, and Capso do not have a verified x86_64 slice in this report. eSearch does, by asset name. Flameshot’s Intel asset name is actively misleading.
- Cap’s SPDX license is unset in the GitHub API. A directory site calls it AGPL-3.0. Those are not the same evidence.
- No app in this pass was timed, and no scrolling claim was tested in Safari, Chrome, Terminal, or Xcode.

**Questions that change the plan**

1. Which three CleanShot actions happen most weeks: copy-and-annotate, scrolling capture, pin, OCR, GIF, or a share link?
2. May a capture be uploaded, or must the default build be unable to send one?
3. Is personal-use freeware acceptable, or does the license need to cover commercial use with no nag screen?
4. Is the only target this 2019 Intel Mac through Tahoe 26, or a later Apple-silicon Mac as well?
5. Is a $12 one-time tool an acceptable stop, or is the requirement a tool with source you control?
6. For redaction, is a baked-in blur enough, or do you need the harsher pixelate and solid-fill behavior?
7. How long should history live, and should older items keep the pre-redaction original?

If the answers are “clipboard annotations, nothing uploaded, this Intel Mac, blur is enough,” the built-in tools plus a trial of macshot are the whole project. A new app starts to make sense only after that trial fails in a specific, repeated way.

## Source list

**CleanShot:** [cleanshot.com/features](https://cleanshot.com/features), [cleanshot.com/pricing](https://cleanshot.com/pricing), [cleanshot.com/changelog](https://cleanshot.com/changelog), [cleanshot.com/faq](https://cleanshot.com/faq), [cleanshot.com/docs-api](https://cleanshot.com/docs-api), [cleanshot.com/product/cloud](https://cleanshot.com/product/cloud), [cleanshot.com/cloud/subprocessors](https://cleanshot.com/cloud/subprocessors), [cleanshot.com/why-updates-expire](https://cleanshot.com/why-updates-expire), [TidBITS on 5.0](https://tidbits.com/watchlist/cleanshot-x-5-0/).

**Apple:** [Take screenshots or screen recordings](https://support.apple.com/guide/mac-help/take-screenshots-or-screen-recordings-mh26782/mac), [Tahoe 26 compatibility](https://support.apple.com/en-us/122867), [Identify your MacBook Pro](https://support.apple.com/en-in/108052), [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), [SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager), [WWDC23 ScreenCaptureKit](https://developer.apple.com/videos/play/wwdc2023/10136/), [Intel apps and Rosetta](https://support.apple.com/en-ie/102527).

**Alternatives:** [shottr.cc](https://shottr.cc/), [shottr.cc/purchase.html](https://shottr.cc/purchase.html), [snipaste.com](https://snipaste.com/), [Snipaste pro wiki](https://github.com/Snipaste/feedback/wiki/%E4%B8%93%E4%B8%9A%E7%89%88), [xnapper.com/es/pricing](https://xnapper.com/es/pricing), [xnapper.com/changelog](https://xnapper.com/changelog), [Snagit system requirements](https://www.techsmith.com/snagit/system-requirements/), [TechSmith macOS matrix](https://support.techsmith.com/hc/en-us/articles/219910027-What-Version-of-macOS-Is-Required-for-TechSmith-Products), [zight.com/mac](https://zight.com/mac), [Zight plans](https://support.zight.com/hc/en-us/articles/5825001220631-Plans-Pricing-and-Plan-Changes), [Monosnap plan comparison](https://monosnap.zendesk.com/hc/en-us/articles/5551061095698-Compare-Monosnap-Plans), [Screen Studio system requirements](https://screen.studio/guide/system-requirements).

**GitHub, retrieved 22 September 2026:** [flameshot](https://github.com/flameshot-org/flameshot), [issue 4754](https://github.com/flameshot-org/flameshot/issues/4754), [v14.0.0](https://github.com/flameshot-org/flameshot/releases/tag/v14.0.0), [Homebrew cask](https://github.com/Homebrew/homebrew-cask/blob/main/Casks/f/flameshot.rb), [ShareX](https://github.com/ShareX/ShareX), [Cap](https://github.com/CapSoftware/Cap), [Kap v3.6.0](https://github.com/wulkano/Kap/releases/tag/v3.6.0), [QuickRecorder 1.6.9](https://github.com/lihaoyun6/QuickRecorder/releases/tag/1.6.9), [eSearch 15.5.1](https://github.com/xushengfeng/eSearch/releases/tag/15.5.1), [macshot](https://github.com/sw33tLie/macshot), [macshot v4.2.1](https://github.com/sw33tLie/macshot/releases/tag/v4.2.1), [TRex](https://github.com/amebalabs/TRex), [Capso license](https://github.com/lzhgus/Capso/blob/main/LICENSE), [ScrollSnap](https://github.com/Brkgng/ScrollSnap), [scap](https://github.com/jaywcjlove/scap), [SwiftShot](https://github.com/Amitdvl/SwiftShot), [ScreenCap](https://github.com/8tp/ScreenCap), [Mio forum post](https://forums.swift.org/t/mio-a-tiny-open-source-macos-screenshot-utility-built-with-swiftui-screencapturekit/87099).
