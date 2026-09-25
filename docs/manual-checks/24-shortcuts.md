# Shortcut defaults and remapping — manual checklist

Not run by the implementer. Use only an approved signed build and synthetic test-pattern windows; capture and clipboard actions require the operator's authorization.

Record date, macOS build, reviewed commit, architecture, code signature, keyboard layout, display layout and Screen Recording permission state. Record each result and any duplicate activation. Record which architecture ran. arm64 stays unexecuted until an Apple silicon run exists.

1. Quit any other screenshot app that uses ⌘⇧3/4/5, including CleanShot. Start Frisket with fresh shortcut preferences. The menu shows ⌘⇧4 Capture Area, ⌘⇧5 Capture Window, ⌘⇧3 Capture Full Screen, ⌘⇧2 Focus Latest Thumbnail, and ⌘⇧1 History. If macOS still had those screenshot shortcuts, Frisket turns them off.
2. Press Command–Shift–4 once: exactly one Frisket Area selector, no macOS screenshot UI. The selector shows the selection size. Cancel with Esc.
3. Press Command–Shift–3 once against the test pattern: exactly one Frisket Full Screen capture, no macOS screenshot.
4. Press Command–Shift–5: exactly one Frisket window selector. Cancel with Esc. Press Command–Shift–2: focus the latest thumbnail exactly once, with no capture. Press Command–Shift–1: History opens, with no capture. Check with another application frontmost and across Spaces.
5. In Settings, click Change and press a new shortcut for each action. Verify the new binding works and the old binding no longer fires. Restart and verify persistence. Verify the menu shows the same shortcut. Restore Default and verify the number-row binding returns.
6. Try a binding that is still an enabled macOS shortcut and is not one Frisket has turned off. Expect a collision warning and the previous Frisket binding to remain active.
7. Try a binding already assigned to another Frisket action. Expect a duplicate warning and unchanged bindings.
8. Restore macOS screenshot shortcuts from Settings. Frisket must stop firing ⌘⇧3/4/5/6 while macOS owns them again. Turn them off from Settings and confirm the number row works again.
9. Occupy a candidate binding in another Carbon-hot-key app. Apply it in Frisket: expect a registration warning and the old binding to remain usable.
10. With a test build injecting a failed or malformed system-shortcut query, try startup and remapping: no unverified binding should be activated or persisted. On dispatch, an unverifiable system list must suppress Frisket's action.
11. Use keyboard navigation and VoiceOver to activate Change, press a shortcut, read warnings, and restore defaults. Defaults undergo the same validation as remaps.
