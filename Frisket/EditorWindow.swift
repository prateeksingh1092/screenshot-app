import AppKit
import FrisketCore

/// Shows the rendered document and hands each drag to the active tool. The canvas is one
/// labelled element; its contents are exempt from VoiceOver and keyboard operation.
@MainActor final class EditorCanvasView: NSView {
    var rendered: NSImage? { didSet { needsDisplay = true } }
    var documentSize: CGSize { didSet { needsDisplay = true } }
    var onDrag: ((CGPoint, CGPoint) -> Void)?
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    init(documentSize: CGSize) {
        self.documentSize = documentSize
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Capture canvas. Drag with the pointer to crop or add a Solid redaction.")
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    private var zoom: CGFloat {
        guard documentSize.width > 0, documentSize.height > 0 else { return 0 }
        return min(bounds.width / documentSize.width, bounds.height / documentSize.height, 4)
    }

    private var imageRect: CGRect {
        let size = CGSize(width: documentSize.width * zoom, height: documentSize.height * zoom)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private func documentPoint(_ event: NSEvent) -> CGPoint? {
        guard zoom > 0 else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max((point.x - imageRect.minX) / zoom, 0), documentSize.width),
                       y: min(max((point.y - imageRect.minY) / zoom, 0), documentSize.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()
        rendered?.draw(in: imageRect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true,
                       hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)])
        guard let start = dragStart, let current = dragCurrent else { return }
        // A neutral outline only; the rendered document shows the real result after the drag.
        let outline = NSBezierPath(rect: CGRect(x: imageRect.minX + min(start.x, current.x) * zoom,
                                                y: imageRect.minY + min(start.y, current.y) * zoom,
                                                width: abs(current.x - start.x) * zoom,
                                                height: abs(current.y - start.y) * zoom))
        outline.lineWidth = 1
        outline.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.selectedContentBackgroundColor.setStroke()
        outline.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = documentPoint(event)
        dragCurrent = dragStart
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = documentPoint(event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let start = dragStart, let end = documentPoint(event) { onDrag?(start, end) }
        dragStart = nil
        dragCurrent = nil
        needsDisplay = true
    }
}

/// A plain AppKit editor for one pending capture: no document architecture, autosave,
/// window restoration, disk image cache or Live Text. The original exists only in memory
/// here and is released when the window closes.
@MainActor final class EditorWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let canvas: EditorCanvasView
    private let base: Bitmap
    private var documentSize: CGSize
    private var edits: DocumentEdits
    private var undoStack: [DocumentEdits] = []
    private let textTool = TextTool()
    private let tools: [any EditorTool]
    private let labelField = NSTextField(string: "A")
    private var activeTool: Int = 0
    private var toolButtons: [NSButton] = []
    private let undoButton = NSButton(title: "Undo", target: nil, action: nil)
    private let closeButton = NSButton(title: "Close Without Changes", target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let dragWell = HistoryDragView()
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)
    var onFileDrag: ((NSView, NSEvent) -> Void)?
    var currentEdits: DocumentEdits { edits }
    var dragPreview: NSImage? { canvas.rendered }
    private var finishing = false
    /// Close only after the command accepts the edits (or the unchanged close).
    private var finish: ((EditorLeave) async -> Bool)?
    private var promptOpen = false

    init?(base: Bitmap, scale: Double, screen: NSScreen?, finish: @escaping (EditorLeave) async -> Bool) {
        guard let edits = DocumentEdits(scale: scale) else { return nil }
        self.base = base
        self.edits = edits
        self.finish = finish
        tools = [SolidRedactionTool(), CropTool(), ArrowTool(), RectangleTool(), textTool, BlurTool(), MagnifyTool()]
        documentSize = CGSize(width: Double(base.width) / scale, height: Double(base.height) / scale)
        canvas = EditorCanvasView(documentSize: documentSize)
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let barHeight: CGFloat = 56
        let size = CGSize(width: min(max(documentSize.width, 840), visible.width * 0.85),
                          height: min(max(documentSize.height, 320), visible.height * 0.85 - barHeight) + barHeight)
        window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Edit Capture"
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 840, height: 240)
        window.delegate = self

        let content = NSView(frame: CGRect(origin: .zero, size: size))
        canvas.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height - barHeight)
        canvas.autoresizingMask = [.width, .height]
        canvas.onDrag = { [weak self] start, end in self?.applyDrag(from: start, to: end) }
        let bar = NSStackView(frame: CGRect(x: 0, y: size.height - barHeight, width: size.width, height: barHeight))
        bar.autoresizingMask = [.width, .minYMargin]
        bar.orientation = .horizontal
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        for (index, tool) in tools.enumerated() {
            let button = NSButton(title: tool.title, target: self, action: #selector(selectTool(_:)))
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .push
            button.tag = index
            button.keyEquivalent = tool.keyEquivalent
            button.keyEquivalentModifierMask = []
            button.setAccessibilityLabel(tool.accessibilityLabel)
            button.toolTip = "\(tool.title) (\(tool.keyEquivalent.uppercased()))"
            toolButtons.append(button)
            bar.addView(button, in: .leading)
        }
        labelField.placeholderString = "Label"
        labelField.setAccessibilityLabel("Annotation label text")
        labelField.bezelStyle = .roundedBezel
        labelField.frame.size.width = 72
        bar.addView(labelField, in: .leading)
        textTool.text = { [weak labelField] in labelField?.stringValue ?? "A" }
        configure(undoButton, action: #selector(undo), key: "z", modifiers: .command,
                  label: "Undo last edit", tip: "Undo last edit (⌘Z)")
        configure(closeButton, action: #selector(closeWithoutChanges), key: "\u{1b}", modifiers: [],
                  label: "Close editor without changes", tip: "Close without changes (Esc)")
        configure(copyButton, action: #selector(copyRendered), key: "c", modifiers: .command,
                  label: "Copy the edited capture", tip: "Copy the edited result (⌘C)")
        configure(saveButton, action: #selector(saveRendered), key: "s", modifiers: .command,
                  label: "Save the edited capture", tip: "Save the edited result (⌘S)")
        configure(doneButton, action: #selector(done), key: "\r", modifiers: [],
                  label: "Done: keep the redacted capture", tip: "Finish editing and keep the redacted result (Return)")
        dragWell.setAccessibilityLabel("Drag the edited capture")
        dragWell.toolTip = "Drag the edited result"
        dragWell.setFrameSize(NSSize(width: 56, height: 36))
        dragWell.onDrag = { [weak self] view, event in
            guard let self, !self.finishing else { return }
            self.onFileDrag?(view, event)
        }
        for button in [undoButton, closeButton, copyButton, saveButton, doneButton] { bar.addView(button, in: .trailing) }
        bar.addView(dragWell, in: .trailing)
        content.addSubview(canvas)
        content.addSubview(bar)
        window.contentView = content
        window.initialFirstResponder = toolButtons.first
        refresh()
    }

    private func configure(_ button: NSButton, action: Selector, key: String, modifiers: NSEvent.ModifierFlags,
                           label: String, tip: String) {
        button.target = self
        button.action = action
        button.bezelStyle = .push
        button.keyEquivalent = key
        button.keyEquivalentModifierMask = modifiers
        button.setAccessibilityLabel(label)
        button.toolTip = tip
    }

    func show() {
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: "Editor ready. Solid redaction tool selected.",
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    private var unchanged: Bool {
        edits.redactions.isEmpty && edits.crop == nil && edits.annotations.isEmpty && edits.effects.isEmpty
    }

    private var currentDocumentSize: CGSize {
        if let crop = edits.crop {
            return CGSize(width: crop.width, height: crop.height)
        }
        return CGSize(width: Double(base.width) / edits.scale, height: Double(base.height) / edits.scale)
    }

    private func refresh() {
        documentSize = currentDocumentSize
        canvas.documentSize = documentSize
        canvas.rendered = nil
        let rendered = DocumentRenderer.render(EditorDocument(base: base, edits: edits))
        canvas.rendered = PNGBitmapCodec.image(rendered).map { NSImage(cgImage: $0, size: documentSize) }
        for button in toolButtons {
            button.state = button.tag == activeTool ? .on : .off
            button.isEnabled = !finishing
        }
        undoButton.isEnabled = !finishing && !undoStack.isEmpty
        closeButton.isEnabled = !finishing && unchanged
        copyButton.isEnabled = !finishing
        saveButton.isEnabled = !finishing
        doneButton.isEnabled = !finishing
        dragWell.image = canvas.rendered
        dragWell.alphaValue = finishing ? 0.4 : 1
    }

    private func applyDrag(from start: CGPoint, to end: CGPoint) {
        guard !finishing else { return }
        var next = edits
        guard tools[activeTool].applyDrag(from: start, to: end, to: &next) else { return }
        undoStack.append(edits)
        edits = next
        refresh()
    }

    @objc private func selectTool(_ sender: NSButton) {
        guard !finishing else { return }
        activeTool = sender.tag
        refresh()
    }

    @objc private func undo() {
        guard !finishing else { return }
        guard let previous = undoStack.popLast() else { return }
        edits = previous
        refresh()
    }

    @objc private func closeWithoutChanges() {
        window.performClose(nil)
    }

    @objc private func copyRendered() {
        end(.deliver(edits, .copy))
    }

    @objc private func saveRendered() {
        end(.deliver(edits, .save))
    }

    @objc private func done() {
        end(.finalize(edits))
    }

    func offerToLeave() {
        window.performClose(nil)
    }

    func interruptUnansweredPrompt(_ event: EditorInterruption) {
        guard promptOpen, let leave = EditorLeave.forInterruptedPrompt(event) else { return }
        window.sheets.forEach { window.endSheet($0, returnCode: .abort) }
        end(leave)
    }

    private func end(_ leave: EditorLeave) {
        guard !finishing, let finish else { return }
        finishing = true
        promptOpen = false
        refresh()
        Task {
            guard await finish(leave) else {
                finishing = false
                refresh()
                return
            }
            self.finish = nil
            window.delegate = nil
            window.orderOut(nil)
            window.contentView = nil
            canvas.rendered = nil
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !finishing else { return false }
        if unchanged {
            end(.finalize(nil))
            return false
        }
        let alert = NSAlert()
        alert.messageText = "Keep this edited capture?"
        alert.informativeText = "Finalize writes the edited image to History. Delete capture discards it. Cancel keeps the editor open."
        alert.addButton(withTitle: "Finalize")
        alert.addButton(withTitle: "Delete Capture")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[0].setAccessibilityLabel("Finalize edited capture")
        alert.buttons[1].hasDestructiveAction = true
        alert.buttons[1].setAccessibilityLabel("Delete capture")
        alert.buttons[2].keyEquivalent = "\u{1b}"
        alert.buttons[2].setAccessibilityLabel("Cancel and keep the editor open")
        promptOpen = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.promptOpen = false
            switch response {
            case .alertFirstButtonReturn: self.end(.finalize(self.edits))
            case .alertSecondButtonReturn: self.end(.delete)
            default: break
            }
        }
        return false
    }
}
