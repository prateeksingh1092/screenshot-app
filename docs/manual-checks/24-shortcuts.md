# Shortcut defaults and remapping — manual checklist

Not run by the implementer. Use only an approved signed build and synthetic test-pattern windows; capture and clipboard actions require the operator's authorization.

Record date, macOS build, reviewed commit, architecture, code signature, keyboard layout, display layout and Screen Recording permission state. Record each result and any duplicate activation. Intel x86_64 is the implementation target; arm64 has not been executed.

1. Enable macOS screenshot shortcuts, including Shift–Command–3/4/5/6 (Touch Bar) and their Control variants. Start Frisket with fresh shortcut preferences.
2. Press Control–Option–Command–4 once: exactly one Frisket Area selector, no macOS screenshot UI. Cancel with Esc.
3. Press Control–Option–Command–3 once against the test pattern: exactly one Frisket Full Screen capture, no macOS screenshot.
4. Press Control–Option–Command–T: focus the latest thumbnail exactly once, with no capture. Check with another application frontmost and across Spaces.
5. In Settings remap each of the three actions, apply, verify the new binding works and the old binding no longer fires. Restart and verify persistence. Verify menu labels agree.
6. Try each enabled system screenshot binding (including Touch Bar 6), then another enabled symbolic shortcut customized in System Settings. Expect a collision warning and the previous Frisket binding to remain active.
7. Try a binding already assigned to another Frisket action. Expect a duplicate warning and unchanged bindings.
8. Disable a system shortcut, assign its old binding to Frisket, then enable it again. Frisket must suppress its action when it can see the new collision. Return to a non-conflicting binding.
9. Occupy a candidate binding in another Carbon-hot-key app. Apply it in Frisket: expect a registration warning and the old binding to remain usable.
10. With a test build injecting a failed or malformed system-shortcut query, try startup and remapping: no unverified binding should be activated or persisted. On dispatch, an unverifiable system list must suppress Frisket's action.
11. Use keyboard navigation and VoiceOver to edit key/modifier controls, Apply, read warnings, and restore defaults. Defaults undergo the same validation as remaps.
