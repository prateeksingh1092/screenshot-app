# 06: Capture to Copy through the command layer

**What to build:** in the core package, a capture command produces a Pending capture from a fixture pixel source and a Copy command delivers it to a recording clipboard stand-in, all through the command layer and the Capture lifecycle coordinator. Verified entirely by `swift test`, no app or Xcode needed.

**Blocked by:** 02, 03 (ticket 02 found the Command Line Tools lack the Swift Testing module; running tests needs Xcode's toolchain)

**Status:** resolved (tested on `main` at `d788502`)

- [x] Commands take typed capture identifiers and explicit inputs and return UI-independent results.
- [x] The coordinator reports commit outcomes and delivery outcomes separately; a delivery retry refers to the same revision.
- [x] Duplicate and stale commands (unknown or already-discarded capture) are rejected safely with a typed result.
- [x] A global budget for pending bytes is tracked and a capture beyond it is refused with a typed result.
- [x] The clipboard port accepts image data only; tests assert that no file location is ever written and the port has no read operation.
- [x] Diagnostics: a logging interface accepting only events from a closed set, an error domain and code, and fields from a fixed allowed set; 7-day local retention; a planted-secret test proves pixels, text, and paths can't reach the log.
- [x] Nothing is written under the app-owned root by capture or copy.

## Comments

### 2026-09-22 — coordinator integration and close

- Implemented by Codex (GPT-6 Astra, high); report in `../reports/06-implementer.md`. Merge conflicts with ticket 04's static checks resolved by a fresh Codex session, keeping both tickets' checks and all 21 fixtures.
- Fresh Codex review against `2915182`: Standards 0, Spec 0, verdict merge (`../reviews/06-code-review-codex.md`).
- Integration branch `integrate/06` on Xcode 26.5, x86_64, macOS 26.7 (25G229): root suite 15 tests passed; trial suite 22 tests passed. arm64 was not executed. Real platform adapters arrive in ticket 08.
- `main` fast-forwarded to `d788502`.
