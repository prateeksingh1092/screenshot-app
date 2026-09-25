# Frisket

Frisket is a menu-bar screenshot app for macOS. It captures an area, a window or the full screen, then lets you copy, save, edit, or keep the image in a local History.

It runs on Intel and Apple silicon. The current floor is **macOS 26**.

## Try the shortcuts

Quit any other screenshot app that uses these keys, including CleanShot. Frisket then uses the same number row as the macOS screenshot tool:

| Shortcut | Action |
| --- | --- |
| ⌘⇧4 | Capture an area |
| ⌘⇧5 | Capture a window |
| ⌘⇧3 | Capture the full screen |
| ⌘⇧2 | Focus the latest thumbnail |
| ⌘⇧1 | Open History |

Frisket never changes your macOS settings. If macOS still uses ⌘⇧3, ⌘⇧4, ⌘⇧5 or ⌘⇧6 for its own screenshots, Frisket leaves those shortcuts inactive, and Settings names them:

1. Open **System Settings › Keyboard**, then click **Keyboard Shortcuts…**. Settings' **Open Keyboard Shortcuts…** button takes you there.
2. Choose **Screenshots** and turn off the shortcuts Frisket named.
3. Come back to Frisket; it registers them at once. **Check Again** in Settings does the same.

To give them back to macOS, turn them on again in the same place. An earlier Frisket build turned them off by itself. If it did so on your Mac, Settings shows **Restore macOS screenshot shortcuts**, which turns back on only the ones it changed, and only when you click it.

Click **Change** in Settings and press keys to pick a different shortcut.

The first capture asks for Screen Recording permission. Grant it, then capture again if macOS asks you to reopen Frisket.

## Build

Install Xcode 26.5 or newer, then from this directory:

```sh
xcodebuild -project Frisket.xcodeproj -scheme Frisket \
  -configuration Development -destination 'platform=macOS' \
  -derivedDataPath "$PWD/.build/DerivedData" build
open "$PWD/.build/DerivedData/Build/Products/Development/Frisket.app"
```

A Development build is for the Mac you are on: Intel builds x86_64, Apple silicon builds arm64. The signed Development configuration in this repository uses one development team. On another Mac, override the signing settings with your own team, or build with `CODE_SIGNING_ALLOWED=NO` and open the app locally.

Release is a universal binary (`x86_64` and `arm64`):

```sh
xcodebuild -project Frisket.xcodeproj -scheme Frisket \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$PWD/.build/ReleaseDerivedData" \
  CODE_SIGNING_ALLOWED=NO build
```

There is no notarized download yet. Beta testers clone the repository and build it.

## Tests for contributors

`scripts/test-core.sh` runs the Swift package tests. Using the app — capturing, cancelling, copying — is the check that matters for a beta build.

## Licence

Frisket is MIT. See `LICENSE`. Third-party components are listed in `THIRD-PARTY-NOTICES.md`.
