# Ticket 23: Screen Recording states and recovery

Not executed by the implementer. Run with Prateek; no personal pixels. Record
OS/build, date, commit, architecture, installed path, signature/designated
requirement, display layout/scales, starting permission and each actual result.
Use the signed build/install steps in [app-build.md](../app-build.md), always
`~/Applications/Frisket.app`. On this Intel Mac record **arm64 not executed**.
Do not launch the unsigned verification build.

## Preserve the ticket 08 grant

First record the existing account's grant and do the granted/rebuild checks
below there. Do not reset TCC, remove Frisket from Settings, change its identity,
or clear its defaults. The destructive permission-state scenarios belong in a
separate macOS test account that has never run this bundle, with Prateek's
approval for account setup and that account's signed install. Use the same
bundle identifier, signing requirement and `~/Applications/Frisket.app` path in
that account. TCC and the request-history marker are per user. If an isolated
account is unavailable, mark not-asked/denied/revoked scenarios unexecuted;
never reset the existing grant to make a checklist pass.

`tccutil reset` is optional only if Prateek explicitly chooses to sacrifice a
particular account's grant. It is neither a prerequisite nor a step in this
checklist. Resetting TCC alone does not erase Frisket's request-history marker;
prefer a fresh test account for a truthful not-asked state.

## State scenarios

1. **Granted, existing account:** launch the installed signed bundle. The menu
   icon should have no warning. Use the ticket 08 synthetic helper and capture
   only its known area; confirm a usable thumbnail and Copy using that checklist.
   Do not take a full-screen image under the synthetic-window-only approval.
   Full-screen gating in missing states below takes no pixels; actual full-screen
   capture needs separate explicit authorization and a clean synthetic display.

2. **After re-signing, existing account:** quit, rebuild with the exact same
   signing command and requirement, replace the installed bundle and relaunch.
   Compare the signature and requirement. Repeat the synthetic-area check twice,
   preserving the existing grant throughout. A new prompt is a failure to
   investigate, not an instruction to reset TCC or grant again. If no longer
   authorized, expect warning/recovery, never selection. This is also the
   ticket 08 two-rebuild persistence check.

3. **Not asked, fresh test account:** launch without requesting access. Expect
   the warning icon. Invoke area from both menu and hot key, then full screen
   from menu: each must show recovery without selection or pixels. The panel
   must offer Open Privacy & Security and Quit & Reopen, and a Request Screen
   Recording action. Do not infer virgin TCC state by deleting preferences in
   the existing account; the marker is app history, not a TCC database query.

4. **Denied, test account:** choose Request Screen Recording and deny the macOS
   request. No selection may appear above or below that alert. Retry both tools:
   expect denied recovery. Quit and reopen; it remains denied. Open Privacy &
   Security must reach Screen & System Audio Recording. Record if macOS uses a
   different pane title or refuses the deep link.

5. **Grant / needs relaunch, test account:** enable Frisket in that pane while
   it is running; if offered, choose Later to exercise the old process. Also
   exercise a successful explicit Request Screen Recording. A request reported
   accepted while preflight remains false, or ScreenCaptureKit authorization
   denial with positive preflight, must produce needs-relaunch recovery. Quit &
   Reopen must quit the old PID and open exactly the installed bundle, once.
   Then retry synthetic-area capture. If this OS applies the grant immediately,
   expect granted and record needs-relaunch as not reproducible on this run;
   do not manufacture it by changing the signing identity. A grant visible only
   in Settings while both APIs report refusal cannot be independently proven by
   the app; the same recovery offers Quit & Reopen from denied/revoked too.

6. **Revoked while running, test account:** start granted; leave the process
   running and turn off Frisket in the Screen Recording pane. If macOS offers
   Later, choose it. The menu warning should update within two seconds or when
   the menu opens; both capture commands must return revoked recovery without
   selection. If macOS terminates the process, record that limitation: the next
   process can report denied, not revocation observed in a previous process.
   Restore the grant and recover. Also revoke after selection starts: finish or
   cancel the selection; no captured image may be accepted after permission loss.

7. **Recovery interaction:** use Tab/Shift-Tab, Return/Space, Escape and VoiceOver
   on the panel. With it open, repeated capture hot keys must not start selection.
   With a system request pending, repeated hot keys must not draw an overlay.
   Quit & Reopen must finalize pending area and full-screen captures into History
   before accepting quit. A failed finalization keeps the app and remaining
   captures open without relaunching. An accepted quit starts reopening only
   after termination begins. Confirm the old PID exits and exactly one new
   instance remains at the installed path. Test an ordinary Quit after a failed or cancelled reopen request:
   it must not unexpectedly reopen. Leave the original account's grant intact.

Record failures verbatim without private image data. Runtime behavior, prompt
ordering, Settings routing and actual relaunch are manual acceptance gates;
fixture tests and an unsigned build do not establish them.
