import AppKit
import FrisketCore

/// Shows the rendered document and hands each drag to the active tool. The canvas is one
/// labelled element; its contents are exempt from VoiceOver and keyboard operation.
@MainActor final class EditorCanvasView: NSView {
    enum DragGuide {
        case box, line, crop, label(String)
    }

    var rendered: NSImage? { didSet { needsDisplay = true } }
    var documentSize: CGSize { didSet { needsDisplay = true } }
    var guide: DragGuide = .box { didSet { needsDisplay = true } }
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
        let startView = CGPoint(x: imageRect.minX + start.x * zoom, y: imageRect.minY + start.y * zoom)
        let currentView = CGPoint(x: imageRect.minX + current.x * zoom, y: imageRect.minY + current.y * zoom)
        switch guide {
        case .line:
            let line = NSBezierPath()
            line.move(to: startView)
            line.line(to: currentView)
            line.lineWidth = 3
            NSColor.systemRed.setStroke()
            line.stroke()
        case .label(let text):
            let shown = text.isEmpty ? "Label" : text
            shown.draw(at: startView, withAttributes: [
                .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: NSColor.systemRed
            ])
        case .crop:
            let kept = CGRect(x: min(startView.x, currentView.x), y: min(startView.y, currentView.y),
                              width: abs(currentView.x - startView.x), height: abs(currentView.y - startView.y))
            NSColor.black.withAlphaComponent(0.45).setFill()
            NSBezierPath(rect: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(0, kept.minY - bounds.minY))).fill()
            NSBezierPath(rect: CGRect(x: bounds.minX, y: kept.maxY, width: bounds.width, height: max(0, bounds.maxY - kept.maxY))).fill()
            NSBezierPath(rect: CGRect(x: bounds.minX, y: kept.minY, width: max(0, kept.minX - bounds.minX), height: kept.height)).fill()
            NSBezierPath(rect: CGRect(x: kept.maxX, y: kept.minY, width: max(0, bounds.maxX - kept.maxX), height: kept.height)).fill()
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: kept)
            border.lineWidth = 1
            border.stroke()
        case .box:
            let outline = NSBezierPath(rect: CGRect(x: min(startView.x, currentView.x), y: min(startView.y, currentView.y),
                                                    width: abs(currentView.x - startView.x), height: abs(currentView.y - startView.y)))
            outline.lineWidth = 2
            NSColor.systemRed.setStroke()
            outline.stroke()
        }
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
    private let pixelSize: CGSize
    private let displayScale: Double
    private var documentSize: CGSize
    private var edits: DocumentEdits
    private var undoStack: [DocumentEdits] = []
    private let textTool = TextTool()
    private let hintField = NSTextField(labelWithString: "")
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
    private let placementScreen: NSScreen?
    private static let chrome = EditorWindowLayout.Chrome(toolbarHeight: 118, titlebarHeight: 28)

    init?(base: Bitmap, pixelSize: CGSize? = nil, scale: Double, screen: NSScreen?,
          finish: @escaping (EditorLeave) async -> Bool) {
        guard let edits = DocumentEdits(scale: scale) else { return nil }
        self.base = base
        self.edits = edits
        self.finish = finish
        self.pixelSize = pixelSize ?? CGSize(width: base.width, height: base.height)
        displayScale = EditorProxy.displayScale(fullWidth: Int(self.pixelSize.width), proxyWidth: base.width, scale: scale)
        tools = [SolidRedactionTool(), CropTool(), ArrowTool(), RectangleTool(), textTool, BlurTool(), MagnifyTool()]
        documentSize = CGSize(width: self.pixelSize.width / scale, height: self.pixelSize.height / scale)
        canvas = EditorCanvasView(documentSize: documentSize)
        placementScreen = screen ?? NSScreen.main
        let visible = placementScreen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let chrome = Self.chrome
        let size = EditorWindowLayout.contentSize(document: documentSize, visible: visible.size, chrome: chrome)
        let barHeight = chrome.toolbarHeight
        window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Edit Capture"
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: min(320, size.width), height: min(200, size.height))
        window.maxSize = visible.size
        window.delegate = self

        let content = NSView(frame: CGRect(origin: .zero, size: size))
        canvas.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height - barHeight)
        canvas.autoresizingMask = [.width, .height]
        canvas.onDrag = { [weak self] start, end in self?.applyDrag(from: start, to: end) }
        let toolsRow = NSStackView()
        toolsRow.orientation = .horizontal
        toolsRow.alignment = .centerY
        toolsRow.spacing = 4
        let actionsRow = NSStackView()
        actionsRow.orientation = .horizontal
        actionsRow.alignment = .centerY
        actionsRow.spacing = 4
        for row in [toolsRow, actionsRow] {
            row.setHuggingPriority(.fittingSizeCompression, for: .horizontal)
            row.setClippingResistancePriority(.fittingSizeCompression, for: .horizontal)
        }
        let bar = NSStackView(frame: CGRect(x: 0, y: size.height - barHeight, width: size.width, height: barHeight))
        bar.autoresizingMask = [.width, .minYMargin]
        bar.orientation = .vertical
        bar.alignment = .leading
        bar.spacing = 4
        bar.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        bar.setHuggingPriority(.fittingSizeCompression, for: .horizontal)
        bar.setClippingResistancePriority(.fittingSizeCompression, for: .horizontal)
        for (index, tool) in tools.enumerated() {
            let button = NSButton(title: tool.title, target: self, action: #selector(selectTool(_:)))
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .push
            button.controlSize = .small
            button.tag = index
            button.keyEquivalent = tool.keyEquivalent
            button.keyEquivalentModifierMask = []
            button.setAccessibilityLabel(tool.accessibilityLabel)
            button.toolTip = "\(tool.title) (\(tool.keyEquivalent.uppercased()))"
            toolButtons.append(button)
            toolsRow.addArrangedSubview(button)
        }
        labelField.placeholderString = "Label"
        labelField.stringValue = ""
        labelField.setAccessibilityLabel("Annotation label text")
        labelField.bezelStyle = .roundedBezel
        labelField.controlSize = .small
        labelField.frame.size.width = 140
        labelField.delegate = self
        toolsRow.addArrangedSubview(labelField)
        textTool.text = { [weak labelField] in labelField?.stringValue ?? "" }
        hintField.textColor = .secondaryLabelColor
        hintField.font = .systemFont(ofSize: 11)
        hintField.lineBreakMode = .byTruncatingTail
        hintField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
        for button in [undoButton, closeButton, copyButton, saveButton, doneButton] { actionsRow.addArrangedSubview(button) }
        actionsRow.addArrangedSubview(dragWell)
        bar.addArrangedSubview(toolsRow)
        bar.addArrangedSubview(hintField)
        bar.addArrangedSubview(actionsRow)
        content.addSubview(canvas)
        content.addSubview(bar)
        window.contentView = content
        window.setContentSize(size)
        window.initialFirstResponder = toolButtons.first
        refresh()
    }

    private func configure(_ button: NSButton, action: Selector, key: String, modifiers: NSEvent.ModifierFlags,
                           label: String, tip: String) {
        button.target = self
        button.action = action
        button.bezelStyle = .push
        button.controlSize = .small
        button.keyEquivalent = key
        button.keyEquivalentModifierMask = modifiers
        button.setAccessibilityLabel(label)
        button.toolTip = tip
    }

    func show() {
        if let screen = placementScreen ?? window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            var frame = window.frame
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = visible.midX - frame.width / 2
            frame.origin.y = visible.midY - frame.height / 2
            if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
            if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
            if frame.minX < visible.minX { frame.origin.x = visible.minX }
            if frame.minY < visible.minY { frame.origin.y = visible.minY }
            window.setFrame(frame, display: true)
        } else {
            window.center()
        }
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
        return CGSize(width: pixelSize.width / edits.scale, height: pixelSize.height / edits.scale)
    }

    private func refresh() {
        documentSize = currentDocumentSize
        canvas.documentSize = documentSize
        canvas.rendered = nil
        guard let displayEdits = DocumentEdits(scale: displayScale, crop: edits.crop, redactions: edits.redactions,
                                               annotations: edits.annotations, effects: edits.effects) else { return }
        let rendered = DocumentRenderer.render(EditorDocument(base: base, edits: displayEdits))
        canvas.rendered = PNGBitmapCodec.image(rendered).map { NSImage(cgImage: $0, size: documentSize) }
        for button in toolButtons {
            button.state = button.tag == activeTool ? .on : .off
            button.isEnabled = !finishing
        }
        undoButton.isEnabled = !finishing && !undoStack.isEmpty
        describeActiveTool()
        closeButton.isEnabled = !finishing && unchanged
        copyButton.isEnabled = !finishing
        saveButton.isEnabled = !finishing
        doneButton.isEnabled = !finishing
        dragWell.image = canvas.rendered
        dragWell.alphaValue = finishing ? 0.4 : 1
    }

    private func describeActiveTool() {
        switch tools[activeTool] {
        case is SolidRedactionTool:
            canvas.guide = .box
            hintField.stringValue = "Drag a box. It is painted solid black and stays hidden under blur."
        case is CropTool:
            canvas.guide = .crop
            hintField.stringValue = "Drag the area to keep. Everything outside it is removed."
        case is ArrowTool:
            canvas.guide = .line
            hintField.stringValue = "Drag from the tail to the point."
        case is RectangleTool:
            canvas.guide = .box
            hintField.stringValue = "Drag a rectangle outline."
        case is TextTool:
            canvas.guide = .label(labelField.stringValue)
            hintField.stringValue = "Type letters or digits, then click where the label should start."
        case is BlurTool:
            canvas.guide = .box
            hintField.stringValue = "Drag a box to soften the pixels inside it."
        case is MagnifyTool:
            canvas.guide = .box
            hintField.stringValue = "Drag a box. Those pixels are doubled from its top-left corner."
        default:
            canvas.guide = .box
            hintField.stringValue = "Drag on the image."
        }
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

extension EditorWindow: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard tools[activeTool] is TextTool else { return }
        canvas.guide = .label(labelField.stringValue)
    }
}
