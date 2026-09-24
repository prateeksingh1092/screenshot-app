import AppKit
import FrisketCore
import SwiftUI

@MainActor final class OnboardingPanel: NSWindowController {
    init(content: OnboardingContent, acknowledge: @escaping () -> Void, later: @escaping () -> Void) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = content.title
        panel.level = .normal
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces]
        super.init(window: panel)
        let hosting = NSHostingView(rootView: OnboardingView(content: content,
            continueAction: { [weak self] in self?.close(); acknowledge() },
            later: { [weak self] in self?.close(); later() }))
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

private struct OnboardingView: View {
    let content: OnboardingContent
    let continueAction: () -> Void
    let later: () -> Void
    @FocusState private var continueFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(content.title).font(.headline).accessibilityAddTraits(.isHeader)
            statement(content.screenRecording)
            statement(content.history)
            statement(content.save)
            statement(content.privacy)
            statement(content.shortcuts)
            HStack {
                Button(content.laterTitle, action: later)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(content.laterAccessibilityLabel)
                Spacer()
                Button(content.continueTitle, action: continueAction)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel(content.continueAccessibilityLabel)
                    .focused($continueFocused)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { continueFocused = true }
    }

    private func statement(_ statement: OnboardingContent.Statement) -> some View {
        Text(statement.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(statement.accessibilityLabel)
            .accessibilityValue(statement.text)
    }
}
