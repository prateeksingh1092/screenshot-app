Implemented ticket 41. The app now uses one synchronized `Frisket/` folder, excluding `Info.plist` and `Frisket.entitlements` from membership. Object version remains 77; documentation explains that new app sources need no project-file edit.

- **Equivalence:** baseline, clean post-edit, and final unsigned builds succeeded. The compiled lists remain identical: nine app Swift files and seven core files. All 23 built Info.plist keys and values match, including bundle identifier `io.github.prateeksingh1092.frisket.debug`. Intended entitlements remain `{}`. All build settings, including hardened runtime and plist/entitlement paths, remain unchanged, as do the core dependency/linkage and “Reject Event Taps and Global Monitors” phase. The phase executed in every build; neither excluded file was copied as a resource.
- **Automatic inclusion:** temporary empty `Ticket41SourceProbe.swift` compiled and produced an object file without changing the project checksum. After deletion, the final build removed its stale object and restored the original source list.
- **Tests:** Swift Testing reported 58 tests across eight suites passing; three opt-in tests were skipped. All eight repository checks and 28 fixture cases passed.
- **Regression guard:** added `app-sources` with accepted/rejected fixtures, including nested groups. It rejected the nine original references and passes after conversion, protecting the conflict-reduction workflow.

Detailed snapshots and proof: [41-build-evidence.json](41-build-evidence.json). Raw logs: `.build/ticket-41-evidence/`.

Signed entitlements/runtime flags remain unverified because builds were unsigned. Stopped before review, staging, commits, or ticket status/checkbox changes.
