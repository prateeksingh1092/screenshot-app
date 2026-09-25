import Foundation
import FrisketCore
import Testing

private let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Suite struct OnboardingAndAboutTests {
    @Test func onboardingStatesThePermissionRetentionSaveAndPrivacyLimits() {
        let copy = OnboardingContent.current
        #expect(copy.screenRecording.text.contains("Screen Recording permission"))
        #expect(copy.history.text.contains("30 days or 1 GB, whichever limit is reached first"))
        #expect(copy.save.text.contains("Save keeps a permanent copy"))
        #expect(copy.privacy.text.contains("only from itself, not from apps, devices, or backups"))
        #expect(copy.privacy.text.contains("FileVault is recommended"))
        #expect(copy.shortcuts.text.contains("Command–Shift–4"))
        #expect(copy.shortcuts.text.contains("Command–Shift–3"))
        #expect(!copy.shortcuts.accessibilityLabel.isEmpty)
        #expect(!copy.screenRecording.accessibilityLabel.isEmpty)
        #expect(!copy.history.accessibilityLabel.isEmpty)
        #expect(!copy.save.accessibilityLabel.isEmpty)
        #expect(!copy.privacy.accessibilityLabel.isEmpty)
        #expect(!copy.continueAccessibilityLabel.isEmpty)
        #expect(!copy.laterAccessibilityLabel.isEmpty)
    }

    @Test func onboardingAppearsOnceAndStaysOffAPendingSystemAlert() {
        let first = OnboardingCompletion(isComplete: false)
        #expect(first.shouldPresent)
        #expect(FirstLaunch.surface(onboarding: first, systemAlertPending: false) == .onboarding)
        #expect(FirstLaunch.surface(onboarding: first, systemAlertPending: true) == .hiddenWhileSystemAlertPending)

        let done = first.markComplete()
        #expect(!done.shouldPresent)
        #expect(FirstLaunch.surface(onboarding: done, systemAlertPending: false) == .ready)

        let blocked = FirstLaunch.complete(permission: .notAsked, systemAlertPending: true)
        #expect(blocked.isComplete)
        #expect(!blocked.showsPermissionRecovery)
        let handoff = FirstLaunch.complete(permission: .notAsked, systemAlertPending: false)
        #expect(handoff.showsPermissionRecovery)
        #expect(handoff.permission == .notAsked)
        let granted = FirstLaunch.complete(permission: .granted, systemAlertPending: false)
        #expect(!granted.showsPermissionRecovery)
        let relaunch = FirstLaunch.complete(permission: .needsRelaunch, systemAlertPending: false)
        #expect(relaunch.showsPermissionRecovery)
    }

    @Test func laterKeepsOnboardingDismissedUntilTheNextLaunch() {
        let incomplete = OnboardingCompletion(isComplete: false)
        #expect(FirstLaunch.surface(onboarding: incomplete, systemAlertPending: false) == .onboarding)

        // Later leaves completion unset, including across a permission alert.
        #expect(FirstLaunch.surface(onboarding: incomplete, systemAlertPending: true,
                                    dismissedForLaunch: true) == .hiddenWhileSystemAlertPending)
        #expect(FirstLaunch.surface(onboarding: incomplete, systemAlertPending: false,
                                    dismissedForLaunch: true) == .ready)
        // A new launch uses the same incomplete preference with no dismissal.
        #expect(!incomplete.isComplete)
        #expect(FirstLaunch.surface(onboarding: incomplete, systemAlertPending: false,
                                    dismissedForLaunch: false) == .onboarding)
    }

    /// Ticket 101: the menu can reopen onboarding after it was completed or put off, but never over a system alert.
    @Test func theMenuReopensOnboardingAfterItWasCompleted() {
        let done = OnboardingCompletion(isComplete: true)
        #expect(FirstLaunch.surface(onboarding: done, systemAlertPending: false) == .ready)
        #expect(FirstLaunch.surface(onboarding: done, systemAlertPending: false, requested: true) == .onboarding)
        #expect(FirstLaunch.surface(onboarding: OnboardingCompletion(isComplete: false), systemAlertPending: false,
                                    dismissedForLaunch: true, requested: true) == .onboarding)
        #expect(FirstLaunch.surface(onboarding: done, systemAlertPending: true, requested: true) == .hiddenWhileSystemAlertPending)
    }

    @Test func aboutShowsTheBundleVersionAndThirdPartyNotices() throws {
        let notices = try String(contentsOf: repository.appendingPathComponent("THIRD-PARTY-NOTICES.md"), encoding: .utf8)
        let about = AboutContent(shortVersion: "0.1.0", build: "8", notices: notices)
        #expect(about.versionText == "Version 0.1.0 (8)")
        #expect(about.versionAccessibilityLabel == "Version 0.1.0, build 8")
        #expect(about.noticeHeadings == [
            "GRDB.swift — MIT",
            "Matt Pocock skills — MIT",
        ])
        #expect(about.notices == notices)
        // D17: About shows formatted text, not Markdown source (ticket 81).
        #expect(about.noticeBlocks.compactMap { if case let .heading(text) = $0 { text } else { nil } } == about.noticeHeadings)
        #expect(about.noticeBlocks.contains { if case let .preformatted(text) = $0 { text.contains("Permission is hereby granted") } else { false } })
        for block in about.noticeBlocks {
            let shown: String
            switch block {
            case let .heading(text), let .preformatted(text): shown = text
            case let .paragraph(text): shown = String(text.characters)
            }
            #expect(!shown.contains("```") && !shown.hasPrefix("#"), "\(shown)")
            if case .paragraph = block { #expect(!shown.contains("**") && !shown.contains("`") && !shown.contains("]("), "\(shown)") }
        }
        #expect(!about.noticeBlocks.contains { if case let .paragraph(text) = $0 { String(text.characters).contains("decision") } else { false } })

        #expect(!about.noticesAccessibilityLabel.isEmpty)
        #expect(!about.closeAccessibilityLabel.isEmpty)
        let plist = try Data(contentsOf: repository.appendingPathComponent("Frisket/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        #expect(info?["CFBundleShortVersionString"] as? String == "0.1.0")
        #expect(info?["CFBundleVersion"] as? String == "8")
    }
}
