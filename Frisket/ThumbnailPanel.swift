import AppKit
import SwiftUI
import FrisketCore

@MainActor final class ThumbnailModel: ObservableObject {
    @Published var busy = false
    @Published var copyFailed = false
    @Published var saveFailed = false
    @Published var dragFailed = false
    @Published var dismissFailed = false
    @Published var keptInHistory = false
    @Published var historyCommitted = false
    @Published var copyFocusRequest = UUID()
}

/// Each card control and gesture issues exactly one of these.
struct ThumbnailCardActions {
    let copy: () -> Void
    let save: () -> Void
    let delete: () -> Void
    let close: () -> Void
    let escape: () -> Void
    let swipe: () -> Void
}

private struct ThumbnailCard: View {
    let image: NSImage
    @ObservedObject var model: ThumbnailModel
    let actions: ThumbnailCardActions
    let startDrag: (NSView, NSEvent) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ThumbnailDragWell(image: image, enabled: !model.busy && !model.keptInHistory, start: startDrag)
                .frame(maxWidth: 240, maxHeight: 120).accessibilityLabel("Pending capture preview")
            if !model.keptInHistory {
                ThumbnailCardControls(model: model, actions: actions)
            }
            Text(model.keptInHistory ? "Kept in History" : model.saveFailed ? (model.historyCommitted ? "Kept in History. Save failed. Retry Save or Close." : "Save failed. Check the export folder in Settings, then Retry Save.") : model.dragFailed ? (model.historyCommitted ? "Kept in History. Drag failed. Drag again or Close." : "Drag failed. Drag again or close to keep in History.") : model.dismissFailed ? "Could not keep in History. Retry Close or Copy." : model.copyFailed ? (model.historyCommitted ? "Kept in History. Copy failed. Retry Copy or Close." : "Copy failed. Retry Copy or close to keep in History.") : "Close, swipe, or press Esc to keep in History.")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
        }.padding(14).frame(width: 260)
    }
}

/// The card's controls. Every control has a VoiceOver label and a key.
private struct ThumbnailCardControls: View {
    @ObservedObject var model: ThumbnailModel
    let actions: ThumbnailCardActions
    @FocusState private var copyFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(model.copyFailed ? "Retry Copy" : "Copy", action: actions.copy)
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
                Button(model.saveFailed ? "Retry Save" : "Save", action: actions.save)
                    .keyboardShortcut("s", modifiers: [])
                    .accessibilityLabel(model.saveFailed ? "Retry saving capture" : "Save capture")
            }
            HStack {
                if !model.historyCommitted {
                    Button("Delete Capture", action: actions.delete)
                        .keyboardShortcut(.delete, modifiers: [])
                        .accessibilityLabel("Delete pending capture")
                }
                Button("Close", action: actions.close)
                    .keyboardShortcut("w", modifiers: .command)
                    .accessibilityLabel("Close thumbnail and keep capture in History")
            }
        }.disabled(model.busy)
            .onChange(of: model.copyFocusRequest) { _, _ in
                copyFocused = true
            }
    }
}

/// Recognizes Escape and a horizontal two-finger swipe within this window only.
private final class ThumbnailCardPanel: NSPanel {
    var closeAction: (() -> Void)?
    var escape: (() -> Void)?
    var swipe: (() -> Void)?
    private var swipeDistance = CGSize.zero

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // The standard File > Close Window command uses the same lifecycle exit.
    override func performClose(_ sender: Any?) { closeAction?() }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.charactersIgnoringModifiers == "\u{1b}",
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            escape?()
            return
        }
        if event.type == .scrollWheel, event.hasPreciseScrollingDeltas {
            trackSwipe(event)
        }
        super.sendEvent(event)
    }

    private func trackSwipe(_ event: NSEvent) {
        switch event.phase {
        case .began:
            swipeDistance = .zero
        case .changed:
            swipeDistance.width += event.scrollingDeltaX
            swipeDistance.height += event.scrollingDeltaY
        case .ended:
            if abs(swipeDistance.width) >= 60, abs(swipeDistance.width) > 2 * abs(swipeDistance.height) { swipe?() }
            swipeDistance = .zero
        case .cancelled:
            swipeDistance = .zero
        default:
            break
        }
    }
}

@MainActor final class ThumbnailPanel {
    let revision: CaptureRevision
    let displayID: UInt32?
    let model = ThumbnailModel()
    private let panel: ThumbnailCardPanel
    private var shown = false

    init(revision: CaptureRevision, preview: CGImage, displayID: UInt32?, actions: ThumbnailCardActions,
         startDrag: @escaping (NSView, NSEvent) -> Void) {
        self.revision = revision
        self.displayID = displayID
        panel = ThumbnailCardPanel(contentRect: CGRect(x: 0, y: 0, width: 288, height: 290),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.closeAction = actions.close
        panel.escape = actions.escape
        panel.swipe = actions.swipe
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        // Every Space, including full-screen ones, and unaffected by Mission Control.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        let image = NSImage(cgImage: preview, size: NSSize(width: preview.width, height: preview.height))
        panel.contentView = NSHostingView(rootView: ThumbnailCard(image: image, model: model, actions: actions, startDrag: startDrag))
        panel.setAccessibilityLabel("Pending capture")
    }

    var size: CGSize { panel.frame.size }

    /// Moves the card to its stack slot; the first placement shows and announces it.
    func place(at origin: CGPoint) {
        guard shown else {
            shown = true
            panel.setFrameOrigin(origin)
            panel.orderFrontRegardless()
            NSAccessibility.post(element: panel, notification: .announcementRequested,
                                 userInfo: [.announcement: "Capture ready. Use Frisket’s Focus Latest Thumbnail menu to copy, save, close, or delete.",
                                            .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            return
        }
        guard panel.frame.origin != origin else { return }
        NSAnimationContext.runAnimationGroup { _ in
            panel.animator().setFrameOrigin(origin)
        }
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
