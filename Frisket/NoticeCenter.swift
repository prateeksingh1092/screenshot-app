import AppKit
import SwiftUI
import FrisketCore

/// The one non-modal notice service (DA-5, ticket 76). A failure a Thumbnail can retry stays on that
/// Thumbnail's status line; every `Notice` goes on this notice line: a small panel that never takes focus,
/// near the menu bar on the pointer's display, gone after 8 s. VoiceOver announces each one.
@MainActor final class NoticeCenter {
    private var panel: NSPanel?
    private var hosting: NSHostingView<NoticeLine>?
    private var hide: Task<Void, Never>?
    private static let visibleFor: Duration = .seconds(8)

    func show(_ notice: Notice) {
        let panel = panel ?? makePanel()
        hosting?.rootView = NoticeLine(notice: notice, dismiss: { [weak self] in self?.dismiss() })
        if let size = hosting?.fittingSize { panel.setContentSize(size) }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: frame.maxX - panel.frame.width - 16, y: frame.maxY - panel.frame.height - 12))
        }
        panel.orderFrontRegardless()
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: notice.announcement,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleFor)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func dismiss() {
        hide?.cancel()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 60),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let hosting = NSHostingView(rootView: NoticeLine(notice: Notice(title: "", message: ""), dismiss: {}))
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 12
        glass.contentView = hosting
        panel.contentView = glass
        panel.setAccessibilityRole(.window)
        panel.setAccessibilityLabel("Frisket notice")
        self.panel = panel
        self.hosting = hosting
        return panel
    }
}

private struct NoticeLine: View {
    let notice: Notice
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title).font(.callout.weight(.semibold))
                Text(notice.message).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss notice")
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
    }
}
