import AppKit
import FrisketCore

@MainActor private final class WindowSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// All input belongs to these temporary panels; no event taps or monitors.
@MainActor final class WindowSelectionOverlay: NSObject {
    private var panels: [WindowSelectionPanel] = []
    private var selection: WindowSelection?
    private var highlighted: WindowCandidate?
    private var completion: CheckedContinuation<UInt32?, Never>?
    private var displays = CaptureDisplays([])

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(environmentChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    func select(from selection: WindowSelection) async -> UInt32? {
        let displays = CaptureDisplays(NSScreen.screens.compactMap(\.selectionDisplay))
        guard completion == nil, !selection.candidates.isEmpty, !displays.displays.isEmpty else { return nil }
        self.selection = selection
        self.displays = displays
        let pointer = NSEvent.mouseLocation
        let pointerDisplay = displays.display(at: pointer)   // D14: top row included
        highlighted = selection.window(at: displays.flipped(pointer))
        return await withCheckedContinuation { continuation in
            completion = continuation
            var keyPanel: WindowSelectionPanel?
            for screen in NSScreen.screens {
                let panel = WindowSelectionPanel(contentRect: screen.frame,
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.level = .screenSaver
                panel.hasShadow = false
                panel.hidesOnDeactivate = false
                panel.becomesKeyOnlyIfNeeded = false
                panel.ignoresMouseEvents = false   // D4: clicks in the clear Selection hole stay in Frisket
                panel.acceptsMouseMovedEvents = true
                panel.isReleasedWhenClosed = false
                panel.isRestorable = false
                panel.animationBehavior = .none
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                let view = WindowSelectionView(screenFrame: screen.frame, displays: displays,
                    scale: screen.backingScaleFactor,
                    hover: { [weak self] point in self?.hover(at: point) },
                    accept: { [weak self] in self?.accept() },
                    cycle: { [weak self] direction in self?.cycle(direction) },
                    cancel: { [weak self] in self?.hide() })
                panel.contentView = view
                panels.append(panel)
                panel.orderFrontRegardless()
                if let pointerDisplay, screen.selectionDisplay?.id == pointerDisplay.id { keyPanel = panel }
            }
            redraw()
            if let panel = keyPanel ?? panels.first {
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(panel.contentView)
            }
        }
    }

    func hide() { finish(nil) }

    private func hover(at point: CGPoint) {
        highlighted = selection?.window(at: point)
        redraw()
    }

    private func cycle(_ direction: Int) {
        guard let candidates = selection?.candidates, !candidates.isEmpty else { return }
        let index = candidates.firstIndex(where: { $0.id == highlighted?.id }) ?? (direction > 0 ? -1 : 0)
        highlighted = candidates[(index + direction + candidates.count) % candidates.count]
        redraw()
        if let view = panels.first?.contentView {
            NSAccessibility.post(element: view, notification: .announcementRequested,
                userInfo: [.announcement: "Window selected. Return captures. Escape cancels.",
                           .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }

    private func redraw() {
        for panel in panels {
            (panel.contentView as? WindowSelectionView)?.highlight = highlighted?.frame
        }
    }

    private func accept() { if let highlighted { finish(highlighted.id) } }

    private func finish(_ id: UInt32?) {
        let continuation = completion
        completion = nil
        for panel in panels { panel.orderOut(nil); panel.contentView = nil }
        panels.removeAll()
        selection = nil
        highlighted = nil
        continuation?.resume(returning: id)
    }

    @objc private func environmentChanged() { if completion != nil { finish(nil) } }
}

@MainActor private final class WindowSelectionView: NSView {
    private let screenFrame: CGRect
    private let displays: CaptureDisplays
    private let scale: CGFloat
    private let hover: (CGPoint) -> Void
    private let accept: () -> Void
    private let cycle: (Int) -> Void
    private let cancel: () -> Void
    var highlight: CGRect? { didSet { needsDisplay = true } }
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }

    init(screenFrame: CGRect, displays: CaptureDisplays, scale: CGFloat, hover: @escaping (CGPoint) -> Void,
         accept: @escaping () -> Void, cycle: @escaping (Int) -> Void, cancel: @escaping () -> Void) {
        self.screenFrame = screenFrame
        self.displays = displays
        self.scale = scale
        self.hover = hover
        self.accept = accept
        self.cycle = cycle
        self.cancel = cancel
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Select a window")
        setAccessibilityHelp("Hover and click, or use the arrow keys or Tab to select. Shift-Tab selects the previous window. Return or keypad Enter captures. Escape cancels.")
    }
    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.40).setFill()
        bounds.fill()
        if let highlight {
            let rect = displays.flipped(highlight).offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            drawCutMarks(rect, scale: scale)
            drawSizeBadge("\(Int(highlight.width.rounded())) × \(Int(highlight.height.rounded()))",
                          above: rect, in: bounds)
        }
    }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hover(displays.flipped(CGPoint(x: point.x + screenFrame.minX, y: point.y + screenFrame.minY)))
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseDown(with event: NSEvent) { mouseMoved(with: event); accept() }
    override func cancelOperation(_ sender: Any?) { cancel() }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: cancel()
        case 36, 76: accept()
        case 123, 126: cycle(-1)
        case 124, 125: cycle(1)
        case 48: cycle(event.modifierFlags.contains(.shift) ? -1 : 1)
        default: super.keyDown(with: event)
        }
    }
}
