import Foundation

/// One block of the notices as About shows it: formatted text, not Markdown source (D17, ticket 81).
public enum AboutBlock: Equatable, Sendable {
    case heading(String)
    /// Inline Markdown (bold, code, links) already applied.
    case paragraph(AttributedString)
    /// A fenced licence text, shown verbatim in a monospaced font.
    case preformatted(String)
}

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
    public var noticeBlocks: [AboutBlock]

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
        noticeBlocks = Self.blocks(notices)
    }

    /// Splits the notices document into headings, paragraphs and fenced texts. The document's own
    /// `# ` title is dropped: About already shows its heading.
    static func blocks(_ markdown: String) -> [AboutBlock] {
        var blocks: [AboutBlock] = []
        var paragraph: [String] = []
        var fence: [String]?
        func flush() {
            guard !paragraph.isEmpty else { return }
            let text = paragraph.joined(separator: " ")
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            blocks.append(.paragraph((try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)))
            paragraph = []
        }
        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                if let lines = fence {
                    blocks.append(.preformatted(lines.joined(separator: "\n")))
                    fence = nil
                } else {
                    flush()
                    fence = []
                }
            } else if fence != nil {
                fence?.append(line)
            } else if line.hasPrefix("## ") {
                flush()
                blocks.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else {
                paragraph.append(line.trimmingCharacters(in: .whitespaces))
            }
        }
        flush()
        if let lines = fence { blocks.append(.preformatted(lines.joined(separator: "\n"))) }
        return blocks
    }
}
