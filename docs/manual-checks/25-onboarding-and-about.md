# 25: Onboarding and About

Set up as in [README.md](README.md). Onboarding shows until the preference
`hasCompletedOnboarding` is set. Delete it only in a test account, never on
Prateek's account.

1. **First launch** (test account). Launch the installed app. "What Frisket
   stores" shows before any capture. It says that Frisket needs Screen
   Recording; that History keeps captures for 30 days or 1 GB, then removes the
   oldest; that Save keeps a copy outside History; and that Frisket can't take
   back what it already delivered. VoiceOver reads each statement and both
   buttons. Tab reaches both. Return is Continue; Esc is Later.
2. **Handoff.** Continue closes onboarding first. Then, if Screen Recording is
   missing, the recovery panel from [23](23-permission-states.md) shows. No
   Frisket window covers the macOS alert.
3. **Once.** Relaunch: onboarding doesn't return. Later instead of Continue
   shows it again on the next launch. Onboarding alone doesn't create the
   History folder.
4. **Capture during onboarding.** ⌘⇧4 brings onboarding forward and starts no
   Selection.
5. **About.** About Frisket shows the app's version and the third-party
   notices, as headings and paragraphs, not Markdown source. VoiceOver reads
   them. Esc, Return and ⌘W close it.
