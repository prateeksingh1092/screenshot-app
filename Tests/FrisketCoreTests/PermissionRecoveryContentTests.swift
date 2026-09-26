import FrisketCore
import Testing

/// D34 (ticket 103, decision 100): once macOS has asked, a second Screen Recording request is silent,
/// so the permission message offers only Open System Settings and Quit & Reopen, and says so.
@Suite struct PermissionRecoveryContentTests {
    @Test func afterARefusalTheMessageSendsTheUserToSystemSettingsWithNoRequestButton() {
        for state in [CapturePermissionState.denied, .revokedWhileRunning] {
            let content = PermissionRecoveryContent(state: state)
            #expect(!content.actions.contains(.requestScreenRecording), "\(state)")
            #expect(content.actions == [.openSystemSettings, .quitAndReopen], "\(state)")
            #expect(content.explanation.contains("Turn Frisket on in System Settings"), "\(state)")
            #expect(content.explanation.contains("quit and reopen Frisket if macOS asks"), "\(state)")
            #expect(!content.explanation.contains("Request"), "\(state)")
        }
    }

    @Test func needsRelaunchOffersNoRequest() {
        let content = PermissionRecoveryContent(state: .needsRelaunch)
        #expect(content.actions == [.openSystemSettings, .quitAndReopen])
        #expect(content.explanation.contains("Quit and reopen Frisket"))
    }

    /// Before macOS has asked, the request is the only way to raise its alert (first launch, check 08).
    @Test func onlyAFirstRunStillOffersTheRequest() {
        let content = PermissionRecoveryContent(state: .notAsked)
        #expect(content.actions == [.requestScreenRecording, .openSystemSettings, .quitAndReopen])
        #expect(content.explanation.contains("Request Screen Recording"))
        for state in [CapturePermissionState.granted, .denied, .revokedWhileRunning, .needsRelaunch] {
            #expect(!PermissionRecoveryContent(state: state).actions.contains(.requestScreenRecording), "\(state)")
        }
    }

    @Test func buttonTitlesMatchTheMessage() {
        #expect(PermissionRecoveryAction.requestScreenRecording.title == "Request Screen Recording")
        #expect(PermissionRecoveryAction.openSystemSettings.title == "Open System Settings")
        #expect(PermissionRecoveryAction.quitAndReopen.title == "Quit & Reopen")
    }
}
