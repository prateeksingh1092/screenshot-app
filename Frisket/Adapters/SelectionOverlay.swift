import AppKit
import FrisketCore

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

    func select(on screen: NSScreen, magnifier: SelectionMagnifier? = nil) async -> AreaSelection? {
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
            panel.becomesKeyOnlyIfNeeded = false
            panel.acceptsMouseMovedEvents = true
            panel.isReleasedWhenClosed = false
            panel.isRestorable = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(screen: screen, magnifier: magnifier) { [weak self] rect in
                self?.finish(rect)
            }
            panel.contentView = view
            self.panel = panel
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
        }
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil // Release the magnifier snapshot before final capture.
        panel = nil
    }

    private func finish(_ rect: CGRect?) {
        var selection: AreaSelection?
        if let rect, let screen, let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            selection = AreaSelection(displayID: number.uint32Value, displayFrame: screen.frame,
                                      rect: rect,
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
    private var geometry: SelectionGeometry
    private let displayFrame: CGRect
    private let scale: CGFloat
    private let magnifier: SelectionMagnifier?
    private var pointer: CGPoint
    private var dragging = false
    private var spaceHeld = false
    private var modifiers: SelectionGeometry.Modifiers = []
    private let completion: (CGRect?) -> Void
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }

    init(screen: NSScreen, magnifier: SelectionMagnifier?, completion: @escaping (CGRect?) -> Void) {
        displayFrame = screen.frame
        scale = screen.backingScaleFactor
        geometry = SelectionGeometry(displayFrame: screen.frame, scale: screen.backingScaleFactor)
        pointer = NSEvent.mouseLocation
        self.magnifier = magnifier
        self.completion = completion
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Select capture area. Drag; Shift locks an axis, Option grows from centre, Space moves, arrows nudge one pixel. Shift-arrow resizes one pixel: right/up grows, left/down shrinks. Return captures. Escape cancels.")
    }
    required init?(coder: NSCoder) { nil }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func draw(_ dirtyRect: NSRect) {
        let selection = geometry.rect.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
        NSColor.black.withAlphaComponent(0.24).setFill()
        bounds.fill()
        NSColor.clear.setFill()
        selection.fill(using: .copy)
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: selection.insetBy(dx: 0.5 / scale, dy: 0.5 / scale))
        outline.lineWidth = 1 / scale
        outline.stroke()
        let message = "Shift locks axis · Option centres · Space moves · Arrows nudge · Shift-arrows resize · Return captures · Esc cancels"
        message.draw(at: CGPoint(x: 24, y: 24), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white])
        if let magnifier {
            magnifier.draw(at: CGPoint(x: pointer.x - displayFrame.minX, y: pointer.y - displayFrame.minY), in: bounds)
        } else {
            "Magnifier unavailable".draw(at: CGPoint(x: 24, y: 46),
                withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white])
        }
    }

    private func point(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: local.x + displayFrame.minX, y: local.y + displayFrame.minY)
    }
    private func updateModifiers(_ event: NSEvent) {
        modifiers = []
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if spaceHeld { modifiers.insert(.space) }
    }
    private func updateGeometry() {
        if dragging { geometry.update(to: pointer, modifiers: modifiers) }
        needsDisplay = true
    }
    override func mouseMoved(with event: NSEvent) {
        pointer = point(event)
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        pointer = point(event)
        dragging = true
        updateModifiers(event)
        geometry.begin(at: pointer)
        updateGeometry()
    }
    override func mouseDragged(with event: NSEvent) {
        pointer = point(event)
        updateModifiers(event)
        updateGeometry()
    }
    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        mouseDragged(with: event)
        dragging = false
        acceptSelection()
    }
    private func acceptSelection() {
        if geometry.rect.width >= 1 / scale, geometry.rect.height >= 1 / scale { completion(geometry.rect) }
    }
    override func flagsChanged(with event: NSEvent) {
        updateModifiers(event)
        updateGeometry()
    }
    override func cancelOperation(_ sender: Any?) { completion(nil) }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: completion(nil); return
        case 36, 76: acceptSelection(); return
        case 49:
            spaceHeld = true
            updateModifiers(event)
            updateGeometry()
            return
        case 123: adjustSelection(dx: -1, dy: 0, event: event)
        case 124: adjustSelection(dx: 1, dy: 0, event: event)
        case 125: adjustSelection(dx: 0, dy: -1, event: event)
        case 126: adjustSelection(dx: 0, dy: 1, event: event)
        default: super.keyDown(with: event); return
        }
        needsDisplay = true
    }
    private func adjustSelection(dx: Int, dy: Int, event: NSEvent) {
        if event.modifierFlags.contains(.shift) {
            geometry.resize(dw: dx, dh: dy)
        } else {
            geometry.nudge(dx: dx, dy: dy)
        }
    }
    override func keyUp(with event: NSEvent) {
        guard event.keyCode == 49 else { super.keyUp(with: event); return }
        spaceHeld = false
        updateModifiers(event)
        updateGeometry()
    }
}
