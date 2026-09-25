/// The only copy for first-launch onboarding. The app displays these statements;
/// it does not keep a second wording.
public struct OnboardingContent: Equatable, Sendable {
    public struct Statement: Equatable, Sendable {
        public var accessibilityLabel: String
        public var text: String
    }

    public var title: String
    public var screenRecording: Statement
    public var history: Statement
    public var save: Statement
    public var privacy: Statement
    public var shortcuts: Statement
    public var continueTitle: String
    public var continueAccessibilityLabel: String
    public var laterTitle: String
    public var laterAccessibilityLabel: String

    public static let current = OnboardingContent(
        title: "What Frisket stores",
        screenRecording: Statement(
            accessibilityLabel: "Screen Recording permission",
            text: "Frisket needs the Screen Recording permission to capture the screen. After you continue, Frisket offers that request and stays out of the way of the macOS system alert."
        ),
        history: Statement(
            accessibilityLabel: "History retention",
            text: "History keeps finalized captures for 30 days or 1 GB, whichever limit is reached first. Frisket then removes the oldest History items automatically."
        ),
        save: Statement(
            accessibilityLabel: "Saved copies",
            text: "Save keeps a permanent copy outside History. History retention and deletion leave that copy untouched."
        ),
        privacy: Statement(
            accessibilityLabel: "Privacy limits",
            text: "Frisket can remove captures only from itself, not from apps, devices, or backups it already delivered to. FileVault is recommended."
        ),
        shortcuts: Statement(
            accessibilityLabel: "Capture shortcuts",
            text: "Command–Shift–4 captures an area, Command–Shift–3 the full screen, and Command–Shift–5 a window. Command–Shift–2 focuses the latest thumbnail, and Command–Shift–1 opens History."
        ),
        continueTitle: "Continue",
        continueAccessibilityLabel: "Continue to the Screen Recording permission request",
        laterTitle: "Later",
        laterAccessibilityLabel: "Close onboarding and show it again on the next launch"
    )
}
