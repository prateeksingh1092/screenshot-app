# Ticket 25: Onboarding and About (Prateek)

Not executed by the implementer. No personal pixels. Record date, `sw_vers`,
`uname -m`, `git rev-parse HEAD`, Xcode version, display layout, and Screen
Recording state. On this Intel Mac record **arm64 not executed**. Use the
signed build and install steps in [app-build.md](../app-build.md), always
`~/Applications/Frisket.app`. Do not launch the unsigned verification build.
Do not reset TCC or clear the existing account's Screen Recording grant.

The completion flag is the bundle-scoped defaults key `hasCompletedOnboarding`.
It is not a file under History. Deleting it makes onboarding appear again;
do that only in a test account, not on the account that holds the ticket 08 grant.

1. **First launch.** In a macOS user that has never completed onboarding for
   `io.github.prateeksingh1092.frisket.debug`, launch the installed app. The
   menu-bar app shows "What Frisket stores" before any capture UI. Confirm the
   text states all of the following:
   - Frisket needs the Screen Recording permission.
   - History keeps finalized captures for 30 days or 1 GB, whichever limit is
     reached first, then removes the oldest History items.
   - Save keeps a permanent copy outside History.
   - Frisket can remove captures only from itself, not from apps, devices, or
     backups it already delivered to. FileVault is recommended.
   With VoiceOver, each statement is labelled (Screen Recording permission,
   History retention, Saved copies, Privacy limits) and the buttons announce
   "Continue to the Screen Recording permission request" and "Close onboarding
   and show it again on the next launch". Tab reaches both buttons. Return
   activates Continue. Escape activates Later.

2. **Permission handoff.** Choose Continue. The onboarding window closes
   first. If Screen Recording is not granted, Frisket then shows ticket 23's
   recovery panel, including Request Screen Recording when the policy allows
   it. Choose Request only after that panel is closed. No Frisket window,
   including onboarding, may cover the macOS system alert. Cancel the alert
   or deny it if this is a test account. Do not reset the existing account's
   grant; if that account is already granted, Continue should not request
   permission again.

3. **Once only.** Quit and launch again. Onboarding does not return. Later
   closes onboarding without setting the flag, so the next launch shows it
   again. Confirm `~/Library/Application Support/io.github.prateeksingh1092.frisket.debug/History.noindex`
   was not created merely by completing onboarding.

4. **About.** Choose About Frisket in the status menu. The window shows
   version 0.1.0 (8) and the bundled third-party notices: GRDB.swift (MIT)
   and the Matt Pocock skills (MIT). VoiceOver reads the version and the notices. Escape
   or Return closes the window. Command-W closes it. Tab reaches Close.

5. **Keyboard capture.** With onboarding visible, the capture hot key and
   menu focus that window and do not start a selection. After it is dismissed,
   capture behaviour stays as in the ticket 23 checklist.

Record failures verbatim. Runtime presentation, VoiceOver, and alert ordering
are manual gates. The automated tests and the unsigned build do not establish them.
