import AppKit
import Combine
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
    /// The last Copy Text result, shown on the status line instead of a modal (D8, DA-5).
    @Published var textNotice = ""
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
    @ObservedObject var model: ThumbnailModel
    let actions: ThumbnailCardActions
    let announce: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            if !model.keptInHistory {
                ThumbnailCardControls(model: model, actions: actions)
            }
            if !status.isEmpty {
                Text(status)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(width: 288)
        .onChange(of: status) { _, new in
            if !new.isEmpty { announce(new) }
        }
    }

    private var status: String {
        if model.keptInHistory { return "Kept in History" }
        if !model.textNotice.isEmpty { return model.textNotice }
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
        return ""
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
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("c", modifiers: [])
                    .focused($copyFocused)
                    .accessibilityLabel("Copy capture")
                    .disabled(model.copiedWhilePending)
                symbolButton(model.saveFailed ? "arrow.clockwise" : "square.and.arrow.down",
                             action: actions.save,
                             shortcut: "s",
                             label: model.saveFailed ? "Retry saving capture" : "Save capture")
                if !model.historyCommitted && !model.editingUnavailable {
                    symbolButton("pencil", action: actions.edit, shortcut: "e", label: "Edit capture")
                }
                symbolButton("text.viewfinder", action: actions.copyText, shortcut: "t", label: "Copy recognized text")
            }
            if !model.historyCommitted {
                HStack {
                    symbolButton("trash", action: actions.delete, shortcut: nil, label: "Delete pending capture")
                        .keyboardShortcut(.delete, modifiers: [])
                }
            }
        }
        .buttonStyle(.bordered)
        .disabled(model.busy)
            .onChange(of: model.copyFocusRequest) { _, _ in
                copyFocused = true
            }
    }

    private func symbolButton(_ name: String, action: @escaping () -> Void, shortcut: Character?, label: String) -> some View {
        Button(action: action) {
            Image(systemName: name)
        }
        .accessibilityLabel(label)
        .modifier(OptionalKeyShortcut(shortcut: shortcut))
    }
}

private struct OptionalKeyShortcut: ViewModifier {
    let shortcut: Character?
    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(KeyEquivalent(shortcut), modifiers: [])
        } else {
            content
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
    private var imageWell: ThumbnailDragWellView?
    private var controlGlass: NSGlassEffectView?
    private var controlHost: NSHostingView<ThumbnailCard>?
    private var modelWatch: AnyCancellable?

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
        panel = ThumbnailCardPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 360),
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
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let image = NSImage(cgImage: preview, size: NSSize(width: preview.width, height: preview.height))
        let hosting = NSHostingView(rootView: ThumbnailCard(model: model, actions: actions, announce: { [weak panel] text in
            guard let panel else { return }
            NSAccessibility.post(element: panel, notification: .announcementRequested,
                                 userInfo: [.announcement: text,
                                            .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }))
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 12
        glass.contentView = hosting
        let well = ThumbnailDragWellView()
        well.image = image
        well.dragEnabled = true
        well.onMouseDown = startDrag
        well.wantsLayer = true
        well.layer?.cornerRadius = 8
        well.layer?.masksToBounds = true
        well.setAccessibilityLabel("Pending capture preview")
        let container = NSView()
        container.addSubview(well)
        container.addSubview(glass)
        panel.contentView = container
        self.imageWell = well
        self.controlGlass = glass
        self.controlHost = hosting
        layoutChrome(image: image)
        panel.setAccessibilityRole(.window)
        panel.setAccessibilityTitle("Pending capture")
        panel.setAccessibilityLabel("Pending capture")
        panel.setAccessibilityElement(true)
        modelWatch = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.syncChrome() }
        }
    }

    private func layoutChrome(image: NSImage) {
        let width: CGFloat = 288
        let gap: CGFloat = 8
        let maxImage = CGSize(width: 264, height: 148)
        let aspect = max(image.size.width, 1) / max(image.size.height, 1)
        var imageSize = CGSize(width: maxImage.width, height: maxImage.width / aspect)
        if imageSize.height > maxImage.height {
            imageSize.height = maxImage.height
            imageSize.width = maxImage.height * aspect
        }
        controlHost?.layoutSubtreeIfNeeded()
        let glassHeight = max(controlHost?.fittingSize.height ?? 0, 44)
        let origin = panel.frame.origin
        panel.setContentSize(NSSize(width: width, height: imageSize.height + gap + glassHeight))
        if shown { panel.setFrameOrigin(origin) }
        controlGlass?.frame = NSRect(x: 0, y: 0, width: width, height: glassHeight)
        imageWell?.frame = NSRect(x: (width - imageSize.width) / 2, y: glassHeight + gap,
                                  width: imageSize.width, height: imageSize.height)
    }

    private func syncChrome() {
        imageWell?.dragEnabled = !model.busy && !model.keptInHistory
        if let image = imageWell?.image { layoutChrome(image: image) }
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
