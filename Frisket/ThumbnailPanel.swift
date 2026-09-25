import AppKit
import Combine
import SwiftUI
import FrisketAdapters
import FrisketCore

@MainActor final class ThumbnailModel: ObservableObject {
    @Published var busy = false
    @Published var copyFailed = false
    @Published var saveFailed = false
    @Published var dragFailed = false
    @Published var copiedWhilePending = false
    @Published var dismissFailed = false
    @Published var keptInHistory = false
    /// The pointer is over the card, so it shows its Close × (decision 91).
    @Published var pointerOver = false
    /// The core's status for this Thumbnail (ticket 73); `CaptureSurfaces` applies it after every command.
    @Published var status: ThumbnailStatus = .pending
    @Published var editable = true
    var historyCommitted: Bool { status == .finalized }
    /// The last Copy Text result, shown on the status line instead of a modal (D8, DA-5).
    @Published var textNotice = ""
    /// The Thumbnail has keyboard focus, so it draws a visible focus ring (D12).
    @Published var keyFocused = false
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
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        VStack(spacing: 8) {
            if !model.keptInHistory {
                // Decision 91: the × sits in the glass controls area, beside the five-button row
                // (decision 60), never over the picture. It shows while the pointer is over the card,
                // and always while VoiceOver runs, so VoiceOver can reach it.
                HStack(alignment: .top, spacing: 4) {
                    ThumbnailCardControls(model: model, actions: actions)
                    Spacer(minLength: 0)
                    if model.pointerOver || voiceOver {
                        ThumbnailCloseButton(model: model, close: actions.close)
                    }
                }
            }
            if !status.isEmpty {
                Text(status)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)   // the card has a fixed size (D9); VoiceOver hears the whole status
                    .accessibilityLabel(status.replacingOccurrences(of: "(×)", with: "(Close)"))
            }
        }
        .padding(12)
        .frame(width: 288)
        .overlay {
            if model.keyFocused {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: status) { _, new in
            if !new.isEmpty { announce(new) }
        }
    }

    private var status: String {
        if model.keptInHistory { return "Kept in History" }
        if !model.textNotice.isEmpty { return model.textNotice }
        // Ticket 98: "Close" is the × (decision 91), which shows while the pointer is over the card.
        if model.copiedWhilePending { return "Copied. Could not add to History. Edit, close (×) to try again, or delete." }
        if model.saveFailed {
            return model.historyCommitted
                ? "Kept in History. Save failed. Retry Save or close (×)."
                : "Save failed. Check the export folder in Settings, then Retry Save."
        }
        if model.dragFailed {
            return model.historyCommitted
                ? "Kept in History. Drag failed. Drag again or close (×)."
                : "Drag failed. Drag again or close (×) to add it to History."
        }
        if model.dismissFailed { return "Could not add to History. Close (×) to try again, or Copy." }
        if model.copyFailed {
            return model.historyCommitted
                ? "Kept in History. Copy failed. Retry Copy or close (×)."
                : "Copy failed. Retry Copy or close (×) to add it to History."
        }
        if model.historyCommitted { return "Kept in History" }   // ticket 91: the card stays until it leaves
        return ""
    }
}

/// Decision 91: the hover ×. It is the same exit as swipe and Esc (`ThumbnailExit.close`), and its
/// VoiceOver name matches the card's custom action, which the live harness also presses.
private struct ThumbnailCloseButton: View {
    @ObservedObject var model: ThumbnailModel
    let close: () -> Void

    var body: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .help("Close")
        .accessibilityLabel(model.status == .finalized ? "Close thumbnail" : "Close thumbnail and keep capture in History")
        .disabled(model.busy)
    }
}

/// The card's controls. Every control has a VoiceOver label and a key.
private struct ThumbnailCardControls: View {
    @ObservedObject var model: ThumbnailModel
    let actions: ThumbnailCardActions
    @FocusState private var copyFocused: Bool

    var body: some View {
        // One row (decision 60): Copy, Save, Edit, Copy Text and Delete.
        HStack(spacing: 6) {
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
            if model.editable {
                symbolButton("pencil", action: actions.edit, shortcut: "e", label: "Edit capture")
            }
            symbolButton("text.viewfinder", action: actions.copyText, shortcut: "t", label: "Copy recognized text")
            if model.status == .pending {
                symbolButton("trash", action: actions.delete, shortcut: nil, label: "Delete pending capture")
                    .keyboardShortcut(.delete, modifiers: [])
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

/// Tracks the pointer over the whole card, picture included, while the panel is not key (decision 91).
private final class ThumbnailHoverView: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    // A card that appears under a resting pointer gets no mouseEntered; the first move shows the ×.
    override func mouseMoved(with event: NSEvent) { onHover?(true) }
}

/// Recognizes single-key commands, arrows, Escape, and a horizontal two-finger swipe.
private final class ThumbnailCardPanel: NSPanel {
    var closeAction: (() -> Void)?
    var swipe: (() -> Void)?
    var keyCommand: ((ThumbnailKeyCommand) -> Void)?
    var onBecomeKey: (() -> Void)?
    var onResignKey: (() -> Void)?
    var onKeyFocusChange: ((Bool) -> Void)?
    private var swipeDistance = CGSize.zero

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        super.becomeKey()
        onKeyFocusChange?(true)
        onBecomeKey?()
    }

    override func resignKey() {
        super.resignKey()
        onKeyFocusChange?(false)
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
    let model = ThumbnailModel()
    private let panel: ThumbnailCardPanel
    private var shown = false
    private var imageWell: ThumbnailDragWellView?
    private var controlGlass: NSGlassEffectView?
    private var controlHost: NSHostingView<ThumbnailCard>?
    private var modelWatch: AnyCancellable?
    private let actions: ThumbnailCardActions

    var onBecomeKey: (() -> Void)? {
        didSet { panel.onBecomeKey = onBecomeKey }
    }
    var onResignKey: (() -> Void)? {
        didSet { panel.onResignKey = onResignKey }
    }
    var moveFocus: ((ThumbnailFocusMove) -> Void)?
    var isKey: Bool { panel.isKeyWindow }

    init(revision: CaptureRevision, preview: CGImage, actions: ThumbnailCardActions,
         startDrag: @escaping (NSView, NSEvent) -> Void) {
        self.revision = revision
        self.actions = actions
        panel = ThumbnailCardPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 360),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // D12: a non-activating panel can take keyboard focus from ⌘⇧2 while another app stays
        // active, so C, S, E, T, Delete and Esc reach the Thumbnail, not the frontmost app.
        panel.becomesKeyOnlyIfNeeded = false
        panel.closeAction = actions.close
        panel.swipe = actions.swipe
        panel.onKeyFocusChange = { [weak model] focused in model?.keyFocused = focused }
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
        let container = ThumbnailHoverView()
        container.onHover = { [weak model] inside in
            if model?.pointerOver != inside { model?.pointerOver = inside }
        }
        container.addSubview(well)
        container.addSubview(glass)
        panel.contentView = container
        self.imageWell = well
        self.controlGlass = glass
        self.controlHost = hosting
        layoutChrome(image: image)
        panel.setAccessibilityRole(.window)
        panel.setAccessibilityElement(true)
        syncAccessibility()
        modelWatch = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.syncChrome() }
        }
    }

    /// Every Thumbnail has one fixed size (D9): the capture is aspect-fit in a fixed image area,
    /// and the controls and status line share a fixed area below it.
    private func layoutChrome(image: NSImage) {
        let card = ThumbnailStackLayout.cardSize
        let gap: CGFloat = 8
        let imageArea = CGSize(width: 264, height: 128)
        let glassHeight = card.height - imageArea.height - gap
        let aspect = max(image.size.width, 1) / max(image.size.height, 1)
        var imageSize = CGSize(width: imageArea.width, height: imageArea.width / aspect)
        if imageSize.height > imageArea.height {
            imageSize.height = imageArea.height
            imageSize.width = imageArea.height * aspect
        }
        // Resize only when the size differs. Re-setting the origin on every model change put a card
        // back in its old slot while place(at:) moved it (D9: two cards on one frame).
        if panel.contentRect(forFrameRect: panel.frame).size != card {
            let origin = panel.frame.origin
            panel.setContentSize(card)
            if shown { panel.setFrameOrigin(origin) }
        }
        controlGlass?.frame = NSRect(x: 0, y: 0, width: card.width, height: glassHeight)
        imageWell?.frame = NSRect(x: (card.width - imageSize.width) / 2,
                                  y: glassHeight + gap + (imageArea.height - imageSize.height) / 2,
                                  width: imageSize.width, height: imageSize.height)
    }

    private func syncChrome() {
        imageWell?.dragEnabled = !model.busy && !model.keptInHistory
        if let image = imageWell?.image { layoutChrome(image: image) }
        syncAccessibility()
    }

    /// D16: the name says whether the capture is pending or kept in History, and a finalized
    /// Thumbnail offers no Edit or Delete. Close finalizes a pending capture and only closes a finalized one.
    private func syncAccessibility() {
        let finalized = model.status == .finalized
        let name = finalized ? "Capture kept in History" : "Pending capture"
        panel.setAccessibilityTitle(name)
        panel.setAccessibilityLabel(name)
        // The picture is its own element (D16, ticket 81); a plain NSView is not one by default.
        imageWell?.setAccessibilityElement(true)
        imageWell?.setAccessibilityRole(.image)
        imageWell?.setAccessibilityLabel("\(name) preview")
        let actions = actions
        var custom = [
            NSAccessibilityCustomAction(name: "Copy capture") { [weak self] in self?.onBecomeKey?(); actions.copy(); return true },
            NSAccessibilityCustomAction(name: "Save capture") { [weak self] in self?.onBecomeKey?(); actions.save(); return true }
        ]
        if model.editable {
            custom.append(NSAccessibilityCustomAction(name: "Edit capture") { [weak self] in self?.onBecomeKey?(); actions.edit(); return true })
        }
        custom.append(NSAccessibilityCustomAction(name: "Copy recognized text") { [weak self] in
            self?.onBecomeKey?(); actions.copyText(); return true
        })
        if !finalized {
            custom.append(NSAccessibilityCustomAction(name: "Delete pending capture") { [weak self] in
                self?.onBecomeKey?(); actions.delete(); return true
            })
        }
        custom.append(NSAccessibilityCustomAction(name: finalized ? "Close thumbnail" : "Close thumbnail and keep capture in History") {
            [weak self] in
            self?.onBecomeKey?()
            actions.close()
            return true
        })
        panel.setAccessibilityCustomActions(custom)
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
        // Set directly, not animated: an in-flight animation left the frame at the old slot (D9).
        guard panel.frame.origin != origin else { return }
        panel.setFrameOrigin(origin)
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
