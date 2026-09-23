/// About window content. Version strings come from the app bundle. Third-party
/// notices are the bundled notices document, shown without a second wording.
public struct AboutContent: Equatable, Sendable {
    public var title: String
    public var versionText: String
    public var versionAccessibilityLabel: String
    public var noticesHeading: String
    public var noticesAccessibilityLabel: String
    public var notices: String
    public var closeTitle: String
    public var closeAccessibilityLabel: String
    public var noticeHeadings: [String]

    public init(shortVersion: String, build: String, notices: String) {
        title = "About Frisket"
        versionText = "Version \(shortVersion) (\(build))"
        versionAccessibilityLabel = "Version \(shortVersion), build \(build)"
        noticesHeading = "Third-party notices"
        noticesAccessibilityLabel = "Third-party notices"
        closeTitle = "Close"
        closeAccessibilityLabel = "Close About"
        self.notices = notices
        noticeHeadings = notices.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.hasPrefix("## ") else { return nil }
            return String(line.dropFirst(3))
        }
    }
}
