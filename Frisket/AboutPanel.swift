import AppKit
import FrisketCore
import SwiftUI

enum BundledAbout {
    static func content(bundle: Bundle = .main) -> AboutContent {
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let notices: String
        if let url = bundle.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            notices = text
        } else {
            notices = "Third-party notices could not be loaded."
        }
        return AboutContent(shortVersion: short, build: build, notices: notices)
    }
}

@MainActor final class AboutPanel: NSWindowController {
    init(content: AboutContent) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = content.title
        panel.level = .normal
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        super.init(window: panel)
        let hosting = NSHostingView(rootView: AboutView(content: content, close: { [weak self] in self?.close() }))
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        panel.center()
        panel.setAccessibilityLabel(content.title)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if let window {
            NSAccessibility.post(element: window, notification: .announcementRequested,
                userInfo: [.announcement: window.title, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }
}

private struct AboutView: View {
    let content: AboutContent
    let close: () -> Void
    @FocusState private var closeFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(content.title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(content.versionText)
                .accessibilityLabel(content.versionAccessibilityLabel)
            Text(content.noticesHeading).font(.headline).accessibilityAddTraits(.isHeader)
            ScrollView {
                Text(content.notices)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(content.noticesAccessibilityLabel)
                    .accessibilityValue(content.notices)
            }
            .frame(maxHeight: 320)
            HStack {
                Spacer()
                Button(content.closeTitle, action: close)
                    .keyboardShortcut(.cancelAction)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel(content.closeAccessibilityLabel)
                    .focused($closeFocused)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { closeFocused = true }
    }
}
