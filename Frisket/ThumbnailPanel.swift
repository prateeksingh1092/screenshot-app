import AppKit
import SwiftUI
import FrisketCore

@MainActor final class ThumbnailModel: ObservableObject {
    @Published var busy = false
    @Published var copyFailed = false
    @Published var dragFailed = false
    @Published var dismissFailed = false
    @Published var keptInHistory = false
    @Published var historyCommitted = false
    @Published var copyFocusRequest = UUID()
}

private struct ThumbnailCard: View {
    let image: NSImage
    @ObservedObject var model: ThumbnailModel
    let copy: () -> Void
    let discard: () -> Void
    let dismiss: () -> Void
    let startDrag: (NSView, NSEvent) -> Void
    @FocusState private var copyFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            ThumbnailDragWell(image: image, enabled: !model.busy && !model.keptInHistory, start: startDrag)
                .frame(maxWidth: 240, maxHeight: 150).accessibilityLabel("Pending capture preview")
            if !model.keptInHistory {
                HStack {
                    Button(model.copyFailed ? "Retry Copy" : "Copy", action: copy)
                        .keyboardShortcut("c", modifiers: [])
                        .focused($copyFocused)
                        .overlay {
                            if copyFocused {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.accentColor, lineWidth: 2)
                                    .padding(-3)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityLabel("Copy capture")
                    if !model.historyCommitted {
                        Button("Delete Capture", action: discard)
                            .keyboardShortcut(.delete, modifiers: [])
                            .accessibilityLabel("Delete pending capture")
                    }
                }.disabled(model.busy)
                Button("Dismiss", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Dismiss capture to History")
                    .disabled(model.busy)
            }
            Text(model.keptInHistory ? "Kept in History" : model.dismissFailed ? "Could not keep in History. Retry Dismiss or Copy." : model.dragFailed ? (model.historyCommitted ? "Kept in History. Drag failed." : "Drag failed. Drag again or dismiss to History.") : model.copyFailed ? (model.historyCommitted ? "Kept in History. Copy failed. Retry Copy or Dismiss." : "Copy failed. Retry Copy or dismiss to History.") : "Dismiss to keep in History.")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
        }.padding(14).frame(width: 260)
            .onChange(of: model.copyFocusRequest) { _, _ in
                copyFocused = true
            }
    }
}

@MainActor final class ThumbnailPanel {
    let revision: CaptureRevision
    let model = ThumbnailModel()
    private let panel: SelectionPanel

    init(revision: CaptureRevision, preview: CGImage, screen: NSScreen, offset: Int,
         copy: @escaping () -> Void, discard: @escaping () -> Void, dismiss: @escaping () -> Void,
         startDrag: @escaping (NSView, NSEvent) -> Void) {
        self.revision = revision
        panel = SelectionPanel(contentRect: CGRect(x: 0, y: 0, width: 288, height: 300),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        let image = NSImage(cgImage: preview, size: NSSize(width: preview.width, height: preview.height))
        panel.contentView = NSHostingView(rootView: ThumbnailCard(image: image, model: model, copy: copy, discard: discard, dismiss: dismiss, startDrag: startDrag))
        let frame = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(x: max(frame.minX, frame.maxX - 308 - CGFloat(offset % 3) * 24),
                                     y: frame.minY + 20 + CGFloat(offset % 3) * 24))
        panel.setAccessibilityLabel("Pending capture")
        panel.orderFrontRegardless()
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: "Capture ready. Use Frisket’s Focus Latest Thumbnail menu to copy, dismiss, or delete.",
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
    func focus() {
        panel.makeKeyAndOrderFront(nil)
        // A fresh request also restores Copy focus after tabbing to Delete.
        model.copyFocusRequest = UUID()
    }
    func showKeptInHistory() {
        model.keptInHistory = true
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: "Kept in History",
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
    func close() { panel.orderOut(nil); panel.contentView = nil }
}

private struct ThumbnailDragWell: NSViewRepresentable {
    let image: NSImage
    let enabled: Bool
    let start: (NSView, NSEvent) -> Void

    func makeNSView(context: Context) -> ThumbnailDragWellView {
        let view = ThumbnailDragWellView()
        view.image = image
        view.dragEnabled = enabled
        view.onMouseDown = start
        return view
    }

    func updateNSView(_ view: ThumbnailDragWellView, context: Context) {
        view.image = image
        view.dragEnabled = enabled
        view.onMouseDown = start
        view.needsDisplay = true
    }
}
