# 24: Shortcut defaults and remapping

**What to build:** Frisket's default shortcuts coexist with the macOS screenshot shortcuts, and Prateek can remap every shortcut in Settings with collision warnings.

**Blocked by:** 08, 11

**Status:** in-progress (branch `ticket/24-shortcut-defaults-and-remapping`)

- [ ] Defaults avoid every enabled system screenshot shortcut, including ⇧⌘3/4/5 and the Touch Bar ⇧⌘6 (decision 29).
- [ ] Remapping validates against the enabled system shortcuts and fails closed when it can't verify.
- [ ] Carbon hot keys only.
- [ ] Manual checklist: each default triggers exactly one tool with system shortcuts enabled.

## Comments
