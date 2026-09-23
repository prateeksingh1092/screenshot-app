# 24: Shortcut defaults and remapping

**What to build:** Frisket's default shortcuts coexist with the macOS screenshot shortcuts, and Prateek can remap every shortcut in Settings with collision warnings.

**Blocked by:** 08, 11

**Status:** resolved (tested on `main` at `cd0dd99`; Carbon/system-shortcut coexistence manual pending)

- [x] Defaults avoid every enabled system screenshot shortcut, including ⇧⌘3/4/5 and the Touch Bar ⇧⌘6 (decision 29).
- [x] Remapping validates against the enabled system shortcuts and fails closed when it can't verify.
- [x] Carbon hot keys only.
- [x] Manual checklist: each default triggers exactly one tool with system shortcuts enabled.

## Comments

- **Integration:** `integrate/16-22-24` fast-forwarded `main` to `cd0dd99`. Remappable Carbon hot keys sit beside History and exclusion Settings. Window capture stays menu-only (`ShortcutAction` has no window case). `swift test`: 210 tests in 31 suites passed. Unsigned x86_64 `xcodebuild` succeeded. x86_64 only; arm64 not executed. Coordinator chat after Codex/Other Models limits.
