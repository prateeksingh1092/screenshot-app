# 03: Install Xcode 26.6

**What to build:** Xcode 26.6, the last Xcode for this Intel Mac, is installed and verified so the app target can be built.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Downloaded from Apple, with its code signature checked before first launch.
- [x] The SDK version is pinned and recorded.
- [x] No Apple ID, keychain, or signing change is made in this ticket (ticket 7 covers the signing identity).

## Comments

### 2026-09-22 — installed by Prateek, verified by the coordinator

- Installed from the Mac App Store as **Xcode 26.5 (17F42)**, not 26.6. Prateek chose to accept and pin 26.5 (decision 47); 26.6 can be revisited later.
- `spctl -a -vv`: accepted, source Mac App Store, origin Apple Mac OS Application Signing. Licence accepted by Prateek with `sudo xcodebuild -license`.
- Pinned: macOS SDK 26.5; Apple Swift 6.3.2 (swiftlang-6.3.2.1.108), target x86_64-apple-macosx26.0. Swift Testing is present in the Xcode toolchain.
- The Command Line Tools carry a newer Swift (6.3.3) than this Xcode but no Swift Testing module; tests use Xcode's toolchain through `DEVELOPER_DIR`.
- `xcode-select` points at Xcode, not the Command Line Tools. Pass `DEVELOPER_DIR` explicitly per command.
- No Apple ID, keychain, or signing change was made.
