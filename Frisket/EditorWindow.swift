import AppKit
import FrisketCore

/// The editor's finish and undo actions. They reach the editor as menu or responder actions,
/// never as button key equivalents, so they work however the window is sized (D5).
enum EditorAction {
    case done, copy, save, undo, closeUnchanged
}

/// Letter keys select tools and Return means Done, unless the label field is editing. ⌘C, ⌘S
/// and ⌘Z arrive from the main menu through the responder chain; Esc arrives as cancelOperation.
@MainActor final class EditorKeyWindow: NSWindow {
    var toolKey: ((Character) -> Bool)?
    var perform: ((EditorAction) -> Void)?
    var canPerform: ((EditorAction) -> Bool)?

    override func keyDown(with event: NSEvent) {
        let commandLike = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        switch EditorKey.action(characters: event.charactersIgnoringModifiers, commandLike: commandLike,
                                editingText: firstResponder is NSTextView) {
        case .done:
            request(.done)
            return
        case .tool(let letter):
            if toolKey?(letter) == true { return }
        case nil:
            break
        }
        super.keyDown(with: event)
    }

    private func request(_ action: EditorAction) {
        if canPerform?(action) ?? false { perform?(action) }
    }

    /// Edit › Copy (⌘C) when the label field has no text selection to copy.
    @objc func copy(_ sender: Any?) { request(.copy) }
    /// File › Save (⌘S).
    @objc func saveEditedCapture(_ sender: Any?) { request(.save) }
    /// Edit › Undo (⌘Z). NSWindow answers `undo:` itself, so the override must live here.
    @objc func undo(_ sender: Any?) { request(.undo) }
    /// Esc closes an unchanged editor; with edits it does nothing, and ⌘W asks.
    override func cancelOperation(_ sender: Any?) { request(.closeUnchanged) }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)): canPerform?(.copy) ?? false
        case #selector(saveEditedCapture(_:)): canPerform?(.save) ?? false
        case #selector(undo(_:)): canPerform?(.undo) ?? false
        default: super.validateMenuItem(menuItem)
        }
    }
}

/// The bar along the bottom of the editor's content area: the drag handle, Copy, Save and Done
/// (the default action), placed by `EditorWindowLayout.actionBar` at every width (D5).
@MainActor final class EditorActionBar: NSView {
    private let dragHandle: NSView
    private let copyButton: NSButton
    private let saveButton: NSButton
    private let doneButton: NSButton

    init(dragHandle: NSView, copy: NSButton, save: NSButton, done: NSButton) {
        self.dragHandle = dragHandle
        copyButton = copy
        saveButton = save
        doneButton = done
        super.init(frame: .zero)
        for view in [dragHandle, copy, save, done] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Finish editing")
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        CGRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let bar = EditorWindowLayout.actionBar(width: newSize.width)
        dragHandle.frame = bar.dragHandle
        copyButton.frame = bar.copy
        saveButton.frame = bar.save
        doneButton.frame = bar.done
    }
}

/// Shows the rendered document and hands each drag to the active tool. The canvas is one
/// labelled element; its contents are exempt from VoiceOver and keyboard operation.
@MainActor final class EditorCanvasView: NSView {
    enum DragGuide {
        case box, line, crop, label(String), conceal, soften
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
        setAccessibilityLabel("Capture canvas. Drag to hide pixels with a solid black redaction.")
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
            line.lineWidth = 4
            NSColor.white.setStroke()
            line.stroke()
            line.lineWidth = 2
            NSColor(srgbRed: 1, green: 59 / 255, blue: 48 / 255, alpha: 1).setStroke()
            line.stroke()
        case .label(let text):
            let shown = text.isEmpty ? "Label" : text
            shown.draw(at: startView, withAttributes: [
                .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: NSColor(srgbRed: 1, green: 59 / 255, blue: 48 / 255, alpha: 1)
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
        case .box, .conceal, .soften:
            let outline = NSBezierPath(rect: CGRect(x: min(startView.x, currentView.x), y: min(startView.y, currentView.y),
                                                    width: abs(currentView.x - startView.x), height: abs(currentView.y - startView.y)))
            switch guide {
            case .conceal:
                outline.lineWidth = 4
                NSColor.white.setStroke()
                outline.stroke()
                outline.lineWidth = 2
                NSColor.black.setStroke()
                outline.stroke()
            case .soften:
                outline.lineWidth = 2
                NSColor.labelColor.setStroke()
                outline.stroke()
            default:
                outline.lineWidth = 4
                NSColor.white.setStroke()
                outline.stroke()
                outline.lineWidth = 2
                NSColor(srgbRed: 1, green: 59 / 255, blue: 48 / 255, alpha: 1).setStroke()
                outline.stroke()
            }
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
    private let window: EditorKeyWindow
    private let canvas: EditorCanvasView
    /// The capture decoded once for the preview; `render(edits)` runs off the main actor.
    private let preview: CapturePreview
    private let pixelSize: CGSize
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
    /// The edits the canvas shows, or is rendering now; the main actor only swaps finished images.
    private var renderedEdits: DocumentEdits?
    private var rendering = false
    /// Close only after the command accepts the edits (or the unchanged close).
    private var finish: ((EditorLeave) async -> Bool)?
    private var promptOpen = false
    private let placementScreen: NSScreen?

    init?(preview: CapturePreview, scale: Double, screen: NSScreen?,
          finish: @escaping (EditorLeave) async -> Bool) {
        guard let edits = DocumentEdits(scale: scale) else { return nil }
        self.preview = preview
        self.edits = edits
        self.finish = finish
        pixelSize = CGSize(width: preview.captureWidth, height: preview.captureHeight)
        tools = [SolidRedactionTool(), CropTool(), ArrowTool(), RectangleTool(), textTool, BlurTool(), MagnifyTool()]
        documentSize = CGSize(width: self.pixelSize.width / scale, height: self.pixelSize.height / scale)
        canvas = EditorCanvasView(documentSize: documentSize)
        placementScreen = screen ?? NSScreen.main
        let visible = placementScreen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        window = EditorKeyWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 480),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Edit Capture"
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.delegate = self

        for (index, tool) in tools.enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(selectTool(_:)))
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .texturedRounded
            button.controlSize = .regular
            button.tag = index
            button.keyEquivalent = ""
            if let image = NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.title) {
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageOnly
            }
            button.setAccessibilityLabel(tool.accessibilityLabel)
            button.toolTip = "\(tool.title) (\(tool.keyEquivalent.uppercased()))"
            toolButtons.append(button)
        }
        labelField.placeholderString = "Label"
        labelField.stringValue = ""
        labelField.setAccessibilityLabel("Annotation label text")
        labelField.bezelStyle = .roundedBezel
        labelField.controlSize = .small
        labelField.frame.size = NSSize(width: 140, height: 22)
        labelField.delegate = self
        textTool.text = { [weak labelField] in labelField?.stringValue ?? "" }
        hintField.textColor = .secondaryLabelColor
        hintField.font = .systemFont(ofSize: 12)
        hintField.lineBreakMode = .byWordWrapping
        hintField.maximumNumberOfLines = 3
        hintField.cell?.truncatesLastVisibleLine = false
        // Undo and Close stay in the toolbar; ⌘Z and Esc reach them through the responder chain.
        configure(undoButton, action: #selector(undo), label: "Undo last edit", tip: "Undo last edit (⌘Z)")
        configure(closeButton, action: #selector(closeWithoutChanges),
                  label: "Close editor without changes", tip: "Close without changes (Esc)")
        for button in [undoButton, closeButton] {
            if let image = NSImage(systemSymbolName: Self.actionSymbol(button), accessibilityDescription: button.title) {
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageOnly
                button.title = ""
            }
        }
        // Copy, Save and Done live in the action bar and keep their titles. Their shortcuts come
        // from the main menu (⌘C, ⌘S) and the window (Return), so they work at any width (D5).
        configure(copyButton, action: #selector(copyRendered), label: "Copy edited capture",
                  tip: "Copy the edited result (⌘C)")
        configure(saveButton, action: #selector(saveRendered), label: "Save edited capture",
                  tip: "Save the edited result (⌘S)")
        configure(doneButton, action: #selector(done), label: "Done",
                  tip: "Done: finish editing and add the capture to History (Return)")
        doneButton.bezelColor = .controlAccentColor
        dragWell.setAccessibilityLabel("Drag the edited capture")
        dragWell.toolTip = "Drag the edited result"
        dragWell.layer?.cornerRadius = 0
        dragWell.layer?.masksToBounds = false
        dragWell.onDrag = { [weak self] view, event in
            guard let self, !self.finishing else { return }
            self.onFileDrag?(view, event)
        }
        let toolbar = NSToolbar(identifier: "frisket.editor")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
        window.toolKey = { [weak self] letter in self?.selectTool(letter: letter) ?? false }
        window.perform = { [weak self] action in self?.perform(action) }
        window.canPerform = { [weak self] action in self?.canPerform(action) ?? false }
        let probe = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 800, height: 400))
        let chromeAbove = probe.height - 400
        let hintHeight: CGFloat = 44
        let barHeight = EditorWindowLayout.actionBarHeight
        var size = EditorWindowLayout.contentSize(document: documentSize, visible: visible.size,
            chrome: EditorWindowLayout.Chrome(toolbarHeight: hintHeight + barHeight, titlebarHeight: chromeAbove))
        size.width = max(size.width, min(EditorWindowLayout.defaultContentWidth, visible.width))
        window.contentMinSize = CGSize(width: min(EditorWindowLayout.minimumContentWidth, visible.width),
                                       height: min(hintHeight + barHeight + 80, size.height))
        window.maxSize = visible.size
        let content = NSView(frame: CGRect(origin: .zero, size: size))
        let bar = EditorActionBar(dragHandle: dragWell, copy: copyButton, save: saveButton, done: doneButton)
        bar.frame = CGRect(x: 0, y: 0, width: size.width, height: barHeight)
        bar.autoresizingMask = [.width, .maxYMargin]
        canvas.frame = CGRect(x: 0, y: barHeight, width: size.width, height: max(1, size.height - hintHeight - barHeight))
        canvas.autoresizingMask = [.width, .height]
        canvas.onDrag = { [weak self] start, end in self?.applyDrag(from: start, to: end) }
        hintField.frame = CGRect(x: 12, y: size.height - hintHeight + 6, width: size.width - 24, height: hintHeight - 10)
        hintField.autoresizingMask = [.width, .minYMargin]
        content.addSubview(canvas)
        content.addSubview(hintField)
        content.addSubview(bar)
        window.contentView = content
        window.setContentSize(size)
        window.initialFirstResponder = toolButtons.first
        refresh()
    }

    private static func actionSymbol(_ button: NSButton) -> String {
        switch button.action {
        case #selector(undo): return "arrow.uturn.backward"
        case #selector(closeWithoutChanges): return "xmark"
        default: return "circle"
        }
    }

    private func selectTool(letter: Character) -> Bool {
        guard let index = tools.firstIndex(where: { $0.keyEquivalent == String(letter) }) else { return false }
        activeTool = index
        refresh()
        return true
    }

    private func configure(_ button: NSButton, action: Selector, label: String, tip: String) {
        button.target = self
        button.action = action
        button.bezelStyle = .push
        button.controlSize = .regular
        button.keyEquivalent = ""
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
        let size = currentDocumentSize
        if documentSize != size { documentSize = size }
        if canvas.documentSize != size { canvas.documentSize = size }
        renderLatestEdits()
        for button in toolButtons {
            button.state = button.tag == activeTool ? .on : .off
            button.isEnabled = !finishing
        }
        labelField.isEnabled = !finishing && tools[activeTool] is TextTool
        undoButton.isEnabled = !finishing && !undoStack.isEmpty
        describeActiveTool()
        closeButton.isEnabled = !finishing && unchanged
        copyButton.isEnabled = !finishing
        saveButton.isEnabled = !finishing
        doneButton.isEnabled = !finishing
        dragWell.image = canvas.rendered
        dragWell.alphaValue = finishing ? 0.4 : 1
    }

    /// Renders the current edits off the main actor with the same renderer Done uses. At most one
    /// render runs; edits made meanwhile are rendered next, and older results are still shown
    /// until then. The main actor only swaps the finished image in.
    private func renderLatestEdits() {
        guard !rendering, edits != renderedEdits else { return }
        rendering = true
        let target = edits, size = currentDocumentSize, preview = preview
        renderedEdits = target
        Task { [weak self] in
            let image = await Self.render(preview, target)
            guard let self else { return }
            rendering = false
            if let image, finish != nil {
                canvas.rendered = NSImage(cgImage: image, size: size)
                dragWell.image = canvas.rendered
            }
            if finish != nil { renderLatestEdits() }
        }
    }

    @concurrent private nonisolated static func render(_ preview: CapturePreview, _ edits: DocumentEdits) async -> CGImage? {
        try? preview.render(edits)
    }

    private func describeActiveTool() {
        switch tools[activeTool] {
        case is SolidRedactionTool:
            canvas.guide = .conceal
            hintField.stringValue = "Drag a box. It is painted solid black and stays hidden under blur."
            canvas.setAccessibilityLabel("Capture canvas. Drag to hide pixels with a solid black redaction.")
        case is CropTool:
            canvas.guide = .crop
            hintField.stringValue = "Drag the area to keep. Everything outside it is removed."
            canvas.setAccessibilityLabel("Capture canvas. Drag the area to keep.")
        case is ArrowTool:
            canvas.guide = .line
            hintField.stringValue = "Drag from the tail to the point. Drawing does not hide pixels."
            canvas.setAccessibilityLabel("Capture canvas. Drag to draw. Drawing does not hide pixels.")
        case is RectangleTool:
            canvas.guide = .box
            hintField.stringValue = "Drag a rectangle outline. Drawing does not hide pixels."
            canvas.setAccessibilityLabel("Capture canvas. Drag to draw. Drawing does not hide pixels.")
        case is TextTool:
            canvas.guide = .label(labelField.stringValue)
            hintField.stringValue = "Type letters or digits, then click where the label should start. Drawing does not hide pixels."
            canvas.setAccessibilityLabel("Capture canvas. Drag to draw. Drawing does not hide pixels.")
        case is BlurTool:
            canvas.guide = .soften
            hintField.stringValue = "Drag a box to soften the pixels inside it. Blur does not hide pixels. Use Solid Redaction to conceal."
            canvas.setAccessibilityLabel("Capture canvas. Drag to blur. Blur does not hide pixels. Use Solid Redaction to conceal.")
        case is MagnifyTool:
            canvas.guide = .soften
            hintField.stringValue = "Drag a box. Those pixels are doubled from its top-left corner. Magnify does not hide pixels. Use Solid Redaction to conceal."
            canvas.setAccessibilityLabel("Capture canvas. Drag to magnify. Magnify does not hide pixels. Use Solid Redaction to conceal.")
        default:
            canvas.guide = .box
            hintField.stringValue = "Drag on the image."
            canvas.setAccessibilityLabel("Capture canvas. Drag on the image.")
        }
        doneButton.toolTip = edits.redactions.isEmpty
            ? "Done: finish editing and add the capture to History (Return)"
            : "Done: finish editing and add the redacted capture to History (Return)"
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

    private func canPerform(_ action: EditorAction) -> Bool {
        guard !finishing, finish != nil else { return false }
        switch action {
        case .done, .copy, .save: return true
        case .undo: return !undoStack.isEmpty
        case .closeUnchanged: return unchanged
        }
    }

    private func perform(_ action: EditorAction) {
        switch action {
        case .done: done()
        case .copy: copyRendered()
        case .save: saveRendered()
        case .undo: undo()
        case .closeUnchanged: closeWithoutChanges()
        }
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

extension EditorWindow: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolButtons.enumerated().map { NSToolbarItem.Identifier("tool-\($0.offset)") }
            + [.init("label"), .flexibleSpace, .init("undo"), .init("close")]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier.rawValue {
        case "label":
            item.view = labelField
            item.label = "Label"
        case "undo": item.view = undoButton; item.label = "Undo"
        case "close": item.view = closeButton; item.label = "Close"
        default:
            guard identifier.rawValue.hasPrefix("tool-"),
                  let index = Int(identifier.rawValue.dropFirst(5)),
                  toolButtons.indices.contains(index) else { return nil }
            item.view = toolButtons[index]
            item.label = tools[index].title
        }
        return item
    }
}

extension EditorWindow: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard tools[activeTool] is TextTool else { return }
        canvas.guide = .label(labelField.stringValue)
    }

    /// Return in the label field ends typing but never means Done; Return again then does.
    /// Esc there closes an unchanged editor, as it does elsewhere, instead of offering completions.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            window.makeFirstResponder(nil)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            window.cancelOperation(nil)
            return true
        default:
            return false
        }
    }
}
