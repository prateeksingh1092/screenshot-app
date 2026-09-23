import AppKit

@MainActor final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Window-local input only. No event monitor is installed, even during selection.
@MainActor final class SelectionOverlay {
    private var panel: SelectionPanel?
    private var completion: CheckedContinuation<AreaSelection?, Never>?
    private var screen: NSScreen?

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
                                              name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func select(on screen: NSScreen) async -> AreaSelection? {
        self.screen = screen
        return await withCheckedContinuation { continuation in
            completion = continuation
            let panel = SelectionPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .screenSaver
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isRestorable = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size)) { [weak self] rect in
                self?.finish(rect)
            }
            panel.contentView = view
            self.panel = panel
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
        }
    }

    func hide() { panel?.orderOut(nil); panel = nil }

    private func finish(_ rect: CGRect?) {
        var selection: AreaSelection?
        if let rect, let screen, let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            selection = AreaSelection(displayID: number.uint32Value, displayFrame: screen.frame,
                                      rect: rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY),
                                      scale: screen.backingScaleFactor)
        }
        hide()
        let continuation = completion
        completion = nil
        screen = nil
        continuation?.resume(returning: selection)
    }

    @objc private func displaysChanged() { if completion != nil { finish(nil) } }
}

@MainActor private final class SelectionView: NSView {
    private var anchor: CGPoint?
    private var selection: CGRect
    private let completion: (CGRect?) -> Void
    override var acceptsFirstResponder: Bool { true }

    init(frame: CGRect, completion: @escaping (CGRect?) -> Void) {
        selection = CGRect(x: max(0, (frame.width - 320) / 2), y: max(0, (frame.height - 180) / 2),
                           width: min(320, frame.width), height: min(180, frame.height))
        self.completion = completion
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Select capture area. Drag, or use arrows to move and Shift arrows to resize. Return captures. Escape cancels.")
    }
    required init?(coder: NSCoder) { nil }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.24).setFill()
        bounds.fill()
        NSColor.clear.setFill()
        selection.fill(using: .copy)
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        outline.lineWidth = 1
        outline.stroke()
        let message = "Drag an area · Arrows move · Shift arrows resize · Return captures · Esc cancels"
        message.draw(at: CGPoint(x: 24, y: 24), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.white])
    }
    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }
    override func mouseDown(with event: NSEvent) {
        anchor = point(event)
        selection = CGRect(origin: point(event), size: .zero)
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let p = point(event)
        selection = CGRect(x: min(p.x, anchor.x), y: min(p.y, anchor.y),
                           width: abs(p.x - anchor.x), height: abs(p.y - anchor.y))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        if selection.width >= 1, selection.height >= 1 { completion(selection) }
    }
    override func cancelOperation(_ sender: Any?) { completion(nil) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { completion(nil); return }
        if event.keyCode == 36 { completion(selection); return }
        let delta: CGPoint
        switch event.keyCode {
        case 123: delta = CGPoint(x: -1, y: 0)
        case 124: delta = CGPoint(x: 1, y: 0)
        case 125: delta = CGPoint(x: 0, y: -1)
        case 126: delta = CGPoint(x: 0, y: 1)
        default: super.keyDown(with: event); return
        }
        if event.modifierFlags.contains(.shift) {
            selection.size.width = min(bounds.maxX - selection.minX, max(1, selection.width + delta.x))
            selection.size.height = min(bounds.maxY - selection.minY, max(1, selection.height + delta.y))
        } else {
            selection.origin.x = min(max(0, selection.minX + delta.x), bounds.maxX - selection.width)
            selection.origin.y = min(max(0, selection.minY + delta.y), bounds.maxY - selection.height)
        }
        needsDisplay = true
    }
}
