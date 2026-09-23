import AppKit
import FrisketCore

@MainActor final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

extension NSScreen {
    var selectionDisplay: SelectionDisplay? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return SelectionDisplay(id: number.uint32Value, frame: frame, scale: backingScaleFactor)
    }
}

/// Window-local input only. No event monitor is installed, even during selection.
@MainActor final class SelectionOverlay {
    private var panels: [UInt32: SelectionPanel] = [:]
    private var completion: CheckedContinuation<AreaSelection?, Never>?
    fileprivate var session: DisplaySelectionSession?

    func select(displays: [SelectionDisplay], pointer: CGPoint,
                magnifiers: [UInt32: SelectionMagnifier]) async -> AreaSelection? {
        guard completion == nil, !displays.isEmpty else { return nil }
        session = DisplaySelectionSession(displays: displays, pointer: pointer)
        return await withCheckedContinuation { continuation in
            completion = continuation
            NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
                name: NSApplication.didChangeScreenParametersNotification, object: nil)
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged),
                name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            for display in displays {
                let panel = SelectionPanel(contentRect: display.frame, styleMask: [.borderless, .nonactivatingPanel],
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
                panel.animationBehavior = .none
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications,
                                            .stationary, .ignoresCycle]
                let view = SelectionView(display: display, magnifier: magnifiers[display.id], overlay: self)
                panel.contentView = view
                panels[display.id] = panel
                panel.orderFrontRegardless()
            }
            focusOrigin()
        }
    }

    /// Also completes a suspended selection if its caller explicitly hides it.
    func hide() { finish(accept: false) }

    fileprivate func redraw() {
        for panel in panels.values { panel.contentView?.needsDisplay = true }
    }

    fileprivate func focusOrigin() {
        guard let id = session?.originDisplay?.id, let panel = panels[id] else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
    }

    fileprivate func finish(accept: Bool) {
        // Re-read before accepting, even if AppKit's change notification is queued.
        session?.updateDisplays(NSScreen.screens.compactMap(\.selectionDisplay))
        var selection: AreaSelection?
        if accept, let display = session?.originDisplay, let rect = session?.acceptedRect {
            selection = AreaSelection(displayID: display.id, displayFrame: display.frame, rect: rect, scale: display.scale)
        }
        // Tear down EVERY panel and frozen preview before resuming the pixel source.
        for panel in panels.values {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels.removeAll()
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        session = nil
        let continuation = completion
        completion = nil
        continuation?.resume(returning: selection)
    }

    @objc private func displaysChanged() {
        session?.updateDisplays(NSScreen.screens.compactMap(\.selectionDisplay))
        if session?.isCancelled == true { finish(accept: false) }
    }

    @objc private func spaceChanged() {
        guard completion != nil else { return }
        displaysChanged()
        guard completion != nil else { return }
        for panel in panels.values {
            // A frozen image of the previous Space is no longer a useful preview.
            (panel.contentView as? SelectionView)?.spaceChanged()
            panel.orderFrontRegardless()
        }
        focusOrigin()
    }
}

@MainActor private final class SelectionView: NSView {
    private unowned let overlay: SelectionOverlay
    private let displayID: UInt32
    private let displayFrame: CGRect
    private let scale: CGFloat
    private var magnifier: SelectionMagnifier?
    private var pointer: CGPoint
    private var dragging = false
    private var spaceHeld = false
    private var modifiers: SelectionGeometry.Modifiers = []
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }

    init(display: SelectionDisplay, magnifier: SelectionMagnifier?, overlay: SelectionOverlay) {
        self.overlay = overlay
        displayID = display.id
        displayFrame = display.frame
        scale = display.scale
        pointer = NSEvent.mouseLocation
        self.magnifier = magnifier
        super.init(frame: CGRect(origin: .zero, size: display.frame.size))
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
        NSColor.black.withAlphaComponent(0.24).setFill()
        bounds.fill()
        guard overlay.session?.originDisplay?.id == displayID, let rect = overlay.session?.rect else {
            "Selection stays on its starting display · Esc cancels".draw(at: CGPoint(x: 24, y: 24),
                withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white])
            return
        }
        let selection = rect.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
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

    func spaceChanged() {
        magnifier = nil
        dragging = false
        spaceHeld = false
        modifiers = []
        needsDisplay = true
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
        if dragging { overlay.session?.update(to: pointer, modifiers: modifiers) }
        needsDisplay = true
    }
    override func mouseMoved(with event: NSEvent) {
        pointer = point(event)
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        pointer = point(event)
        guard overlay.session?.begin(at: pointer) == true else {
            overlay.focusOrigin()
            return
        }
        dragging = true
        updateModifiers(event)
        updateGeometry()
        overlay.redraw()
        overlay.focusOrigin()
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
        if overlay.session?.acceptedRect != nil { overlay.finish(accept: true) }
    }
    override func flagsChanged(with event: NSEvent) {
        updateModifiers(event)
        updateGeometry()
    }
    override func cancelOperation(_ sender: Any?) { overlay.finish(accept: false) }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: overlay.finish(accept: false); return
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
            overlay.session?.resize(dw: dx, dh: dy)
        } else {
            overlay.session?.nudge(dx: dx, dy: dy)
        }
    }
    override func keyUp(with event: NSEvent) {
        guard event.keyCode == 49 else { super.keyUp(with: event); return }
        spaceHeld = false
        updateModifiers(event)
        updateGeometry()
    }
}
