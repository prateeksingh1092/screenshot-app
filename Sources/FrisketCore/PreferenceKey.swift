/// Every key Frisket stores in its bundle-scoped user defaults. A raw value is the stored name,
/// so renaming one loses the user's saved setting. No key names a file or a History path.
public enum PreferenceKey: String, CaseIterable, Sendable {
    case globalShortcuts = "globalShortcuts.v1"
    case thumbnailAutoDismissNever
    case thumbnailAutoDismissSeconds
    case historyRetentionDays
    case historyMaximumMegabytes
    case exportFolder = "exportFolderPath"
    case captureExclusions = "captureExcludedBundleIdentifiers"
    case screenRecordingRequested = "screenRecordingPermissionWasRequested"
    case onboardingCompleted = "hasCompletedOnboarding"
    /// The restore record an earlier build kept when it turned macOS screenshot shortcuts off (DA-2).
    case systemScreenshotShortcutsTurnedOff = "systemScreenshotHotkeys.turnedOffByFrisket"
    /// The editor's last-used styles (ticket 100, decision 93); `EditorStyles` reads and writes them.
    case editorRedactionColour
    case editorInkColour
    case editorArrowStyle
    case editorArrowWidth
    case editorLineWidth
    case editorShapeWidth
    case editorLabelSize
    case editorLabelStyle
}
