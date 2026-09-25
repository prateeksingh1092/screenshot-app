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
    private var spaceGeneration: (() -> UInt64)?
    private var completion: CheckedContinuation<AreaSelection?, Never>?
    fileprivate var session: DisplaySelectionSession?
    private var loupeFeed: LoupeFeed?
    private var loupeDisplayID: UInt32?

    /// `loupe` samples device pixels for the Loupe; nil shows no Loupe.
    func select(displays: [SelectionDisplay], pointer: CGPoint, loupe: LoupeFeed.Capture? = nil,
                spaceGeneration: @escaping () -> UInt64) async -> AreaSelection? {
        guard completion == nil, !displays.isEmpty else { return nil }
        self.spaceGeneration = spaceGeneration
        session = DisplaySelectionSession(displays: displays, pointer: pointer)
        loupeDisplayID = nil
        loupeFeed = loupe.map { capture in
            LoupeFeed(capture: capture) { [weak self] sample, image in self?.showLoupe(image, of: sample) }
        }
        return await withCheckedContinuation { continuation in
            completion = continuation
            NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
                name: NSApplication.didChangeScreenParametersNotification, object: nil)
            for display in displays {
                let panel = SelectionPanel(contentRect: display.frame, styleMask: [.borderless, .nonactivatingPanel],
                                           backing: .buffered, defer: false)
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
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications,
                                            .stationary, .ignoresCycle]
                let view = SelectionView(display: display, overlay: self)
                panel.contentView = view
                panels[display.id] = panel
                panel.orderFrontRegardless()
            }
            focusOrigin()
            // Sampled only once the overlay is on screen, so the capture route can exclude it.
            pointerMoved(to: NSEvent.mouseLocation)
        }
    }

    /// Moves the Loupe with the pointer (global points) and asks for that pixel square.
    fileprivate func pointerMoved(to pointer: CGPoint) {
        guard let feed = loupeFeed, let target = session?.loupeTarget(at: pointer),
              let sample = Loupe.sample(at: target.pointer, on: target.display),
              let view = panels[target.display.id]?.contentView as? SelectionView else {
            hideLoupe()
            return
        }
        if loupeDisplayID != target.display.id { hideLoupe() }
        loupeDisplayID = target.display.id
        view.placeLoupe(beside: target.pointer)
        feed.request(sample)
    }

    private func showLoupe(_ image: CGImage, of sample: LoupeSample) {
        guard sample.displayID == loupeDisplayID,
              let view = panels[sample.displayID]?.contentView as? SelectionView else { return }
        view.showLoupe(image, of: sample)
    }

    private func hideLoupe() {
        loupeDisplayID = nil
        for panel in panels.values { (panel.contentView as? SelectionView)?.hideLoupe() }
    }

    /// Also completes a suspended selection if its caller explicitly hides it.
    func hide() { finish(accept: false) }

    fileprivate func redraw() {
        for panel in panels.values { (panel.contentView as? SelectionView)?.invalidateChangedSelection() }
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
        if accept, let display = session?.originDisplay, let rect = session?.acceptedRect,
           let spaceGeneration {
            selection = AreaSelection(displayID: display.id, displayFrame: display.frame, rect: rect, scale: display.scale,
                                      spaceGeneration: spaceGeneration())
        }
        // Tear down the Loupe and EVERY panel before resuming the pixel source.
        loupeFeed?.stop()
        loupeFeed = nil
        hideLoupe()
        for panel in panels.values {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels.removeAll()
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        spaceGeneration = nil
        session = nil
        let continuation = completion
        completion = nil
        continuation?.resume(returning: selection)
    }

    @objc private func displaysChanged() {
        session?.updateDisplays(NSScreen.screens.compactMap(\.selectionDisplay))
        if session?.isCancelled == true { finish(accept: false) }
    }

    func spaceChanged() {
        guard completion != nil else { return }
        displaysChanged()
        guard completion != nil else { return }
        hideLoupe()
        for panel in panels.values {
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
    private var pointer: CGPoint
    private var dragging = false
    private var spaceHeld = false
    private var modifiers: SelectionGeometry.Modifiers = []
    private var paintedSelection: NSRect = .null
    private let loupe = LoupeView()
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }

    init(display: SelectionDisplay, overlay: SelectionOverlay) {
        self.overlay = overlay
        displayID = display.id
        displayFrame = display.frame
        scale = display.scale
        pointer = NSEvent.mouseLocation
        super.init(frame: CGRect(origin: .zero, size: display.frame.size))
        wantsLayer = true
        addSubview(loupe)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Select capture area")
        setAccessibilityHelp("Drag to select. Shift locks an axis. Option grows from the centre. Space moves the selection. Arrow keys nudge one pixel. Shift-arrow resizes one pixel: right and up grow, left and down shrink. Return or keypad Enter captures. Escape cancels.")
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
        NSColor.black.withAlphaComponent(0.40).setFill()
        dirtyRect.fill()
        guard overlay.session?.originDisplay?.id == displayID, let rect = overlay.session?.rect else {
            drawSolidNotice("Selection stays on the display where it started. Esc cancels.", at: CGPoint(x: 16, y: 16), in: bounds)
            return
        }
        let selection = rect.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
        NSColor.clear.setFill()
        selection.fill(using: .copy)
        drawCutMarks(selection, scale: scale)
        var measurement = "\(Int(selection.width.rounded())) × \(Int(selection.height.rounded()))"
        if let word = quietWord { measurement += "  \(word)" }
        drawSizeBadge(measurement, above: selection, in: bounds)
    }

    /// One quiet word while a modifier changes the gesture. At rest the badge is only the measurement.
    private var quietWord: String? {
        if modifiers.contains(.space) { return "move" }
        if modifiers.contains(.option) { return "from centre" }
        if modifiers.contains(.shift) { return "locked" }
        return nil
    }

    func invalidateChangedSelection() {
        let selection = currentSelectionRect()
        let previous = paintedSelection
        paintedSelection = selection
        var dirty = selection.isNull ? NSRect.null : selection.insetBy(dx: -16, dy: -72)
        if !previous.isNull { dirty = dirty.union(previous.insetBy(dx: -8, dy: -56)) }
        dirty = dirty.union(NSRect(x: 0, y: 0, width: bounds.width, height: 48))
        setNeedsDisplay(dirty)
    }

    /// `pointer` is in global points; the Loupe stays inside this display.
    func placeLoupe(beside pointer: CGPoint) {
        loupe.place(beside: CGPoint(x: pointer.x - displayFrame.minX, y: pointer.y - displayFrame.minY), in: bounds)
    }
    func showLoupe(_ image: CGImage, of sample: LoupeSample) { loupe.show(image, of: sample) }
    func hideLoupe() { loupe.clear() }

    private func currentSelectionRect() -> NSRect {
        guard overlay.session?.originDisplay?.id == displayID, let rect = overlay.session?.rect else { return .null }
        return rect.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
    }

    func spaceChanged() {
        dragging = false
        spaceHeld = false
        modifiers = []
        paintedSelection = .null
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
        invalidateChangedSelection()
    }
    override func mouseMoved(with event: NSEvent) {
        pointer = point(event)
        overlay.pointerMoved(to: pointer)
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
        overlay.pointerMoved(to: pointer)
        overlay.redraw()
        overlay.focusOrigin()
    }
    override func mouseDragged(with event: NSEvent) {
        pointer = point(event)
        updateModifiers(event)
        updateGeometry()
        overlay.pointerMoved(to: pointer)
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
