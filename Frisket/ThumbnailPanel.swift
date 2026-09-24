import AppKit
import SwiftUI
import FrisketCore

@MainActor final class ThumbnailModel: ObservableObject {
    @Published var busy = false
    @Published var copyFailed = false
    @Published var saveFailed = false
    @Published var dragFailed = false
    @Published var copiedWhilePending = false
    @Published var editingUnavailable = false
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
    let edit: () -> Void
    let copyText: () -> Void
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
            Text(status)
                .font(.caption).fixedSize(horizontal: false, vertical: true)
        }.padding(14).frame(width: 260)
    }

    private var status: String {
        if model.keptInHistory { return "Kept in History" }
        if model.copiedWhilePending { return "Copied. Could not keep in History. Edit, retry Close, or delete." }
        if model.saveFailed {
            return model.historyCommitted
                ? "Kept in History. Save failed. Retry Save or Close."
                : "Save failed. Check the export folder in Settings, then Retry Save."
        }
        if model.dragFailed {
            return model.historyCommitted
                ? "Kept in History. Drag failed. Drag again or Close."
                : "Drag failed. Drag again or close to keep in History."
        }
        if model.dismissFailed { return "Could not keep in History. Retry Close or Copy." }
        if model.copyFailed {
            return model.historyCommitted
                ? "Kept in History. Copy failed. Retry Copy or Close."
                : "Copy failed. Retry Copy or close to keep in History."
        }
        return "Close, swipe, or press Esc to keep in History."
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
                Button(model.copiedWhilePending ? "Copied" : model.copyFailed ? "Retry Copy" : "Copy", action: actions.copy)
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
                    .disabled(model.copiedWhilePending)
                Button(model.saveFailed ? "Retry Save" : "Save", action: actions.save)
                    .keyboardShortcut("s", modifiers: [])
                    .accessibilityLabel(model.saveFailed ? "Retry saving capture" : "Save capture")
                if !model.historyCommitted && !model.editingUnavailable {
                    Button("Edit", action: actions.edit)
                        .keyboardShortcut("e", modifiers: [])
                        .accessibilityLabel("Edit capture")
                }
                Button("Copy Text", action: actions.copyText)
                    .keyboardShortcut("t", modifiers: [])
                    .accessibilityLabel("Copy recognized text")
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

/// Recognizes single-key commands, arrows, Escape, and a horizontal two-finger swipe.
private final class ThumbnailCardPanel: NSPanel {
    var closeAction: (() -> Void)?
    var swipe: (() -> Void)?
    var keyCommand: ((ThumbnailKeyCommand) -> Void)?
    var onBecomeKey: (() -> Void)?
    var onResignKey: (() -> Void)?
    private var swipeDistance = CGSize.zero

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        super.becomeKey()
        onBecomeKey?()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func setAccessibilityFocused(_ focused: Bool) {
        super.setAccessibilityFocused(focused)
        if focused { onBecomeKey?() }
        else { onResignKey?() }
    }

    // The standard File > Close Window command uses the same lifecycle exit.
    override func performClose(_ sender: Any?) { closeAction?() }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if let command = ThumbnailKeys.command(characters: event.charactersIgnoringModifiers ?? "",
                                                   keyCode: UInt16(event.keyCode),
                                                   command: modifiers.contains(.command),
                                                   option: modifiers.contains(.option),
                                                   control: modifiers.contains(.control),
                                                   shift: modifiers.contains(.shift)) {
                keyCommand?(command)
                return
            }
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
    var displayID: UInt32?
    let model = ThumbnailModel()
    private let panel: ThumbnailCardPanel
    private var shown = false

    var onBecomeKey: (() -> Void)? {
        didSet { panel.onBecomeKey = onBecomeKey }
    }
    var onResignKey: (() -> Void)? {
        didSet { panel.onResignKey = onResignKey }
    }
    var moveFocus: ((ThumbnailFocusMove) -> Void)?
    var isKey: Bool { panel.isKeyWindow }

    init(revision: CaptureRevision, preview: CGImage, displayID: UInt32?, actions: ThumbnailCardActions,
         startDrag: @escaping (NSView, NSEvent) -> Void) {
        self.revision = revision
        self.displayID = displayID
        panel = ThumbnailCardPanel(contentRect: CGRect(x: 0, y: 0, width: 288, height: 320),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
        panel.closeAction = actions.close
        panel.swipe = actions.swipe
        panel.keyCommand = { [weak self] command in
            self?.onBecomeKey?()
            switch command {
            case .copy: actions.copy()
            case .save: actions.save()
            case .edit: actions.edit()
            case .copyText: actions.copyText()
            case .deleteCapture: actions.delete()
            case .dismiss: actions.escape()
            case .newer: self?.moveFocus?(.newer)
            case .older: self?.moveFocus?(.older)
            }
        }
        panel.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Copy capture") { [weak self] in self?.onBecomeKey?(); actions.copy(); return true },
            NSAccessibilityCustomAction(name: "Save capture") { [weak self] in self?.onBecomeKey?(); actions.save(); return true },
            NSAccessibilityCustomAction(name: "Edit capture") { [weak self] in self?.onBecomeKey?(); actions.edit(); return true },
            NSAccessibilityCustomAction(name: "Copy recognized text") { [weak self] in self?.onBecomeKey?(); actions.copyText(); return true },
            NSAccessibilityCustomAction(name: "Delete pending capture") { [weak self] in self?.onBecomeKey?(); actions.delete(); return true },
            NSAccessibilityCustomAction(name: "Close thumbnail and keep capture in History") { [weak self] in
                self?.onBecomeKey?()
                actions.close()
                return true
            }
        ])
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        // Every Space, including full-screen ones, and unaffected by Mission Control.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        let image = NSImage(cgImage: preview, size: NSSize(width: preview.width, height: preview.height))
        panel.contentView = NSHostingView(rootView: ThumbnailCard(image: image, model: model, actions: actions, startDrag: startDrag))
        panel.setAccessibilityRole(.window)
        panel.setAccessibilityTitle("Pending capture")
        panel.setAccessibilityLabel("Pending capture")
        panel.setAccessibilityElement(true)
    }

    var size: CGSize { panel.frame.size }

    /// Moves the card to its stack slot; the first placement shows and announces it.
    func place(at origin: CGPoint) {
        guard shown else {
            shown = true
            panel.setFrameOrigin(origin)
            panel.orderFrontRegardless()
            NSAccessibility.post(element: panel, notification: .announcementRequested,
                                 userInfo: [.announcement: "Capture ready. Focus Latest Thumbnail, then arrows move, C copies, S saves, E edits, T copies text, Delete deletes, Escape dismisses.",
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
