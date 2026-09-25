import AppKit
import FrisketCore

/// The editor's finish and undo actions. They reach the editor as menu or responder actions,
/// never as button key equivalents, so they work however the window is sized (D5).
enum EditorAction {
    case done, copy, save, undo, redo, closeUnchanged
}

/// Letter keys select tools and Return means Done, unless a label is being typed. ⌘C, ⌘S
/// ⌘Z and ⌘⇧Z arrive from the main menu through the responder chain; Esc arrives as cancelOperation.
@MainActor final class EditorKeyWindow: NSWindow {
    var toolKey: ((Character) -> Bool)?
    var perform: ((EditorAction) -> Void)?
    var canPerform: ((EditorAction) -> Bool)?
    /// Esc first deselects a selected mark (ticket 84); returns false when nothing was selected.
    var deselect: (() -> Bool)?

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

    /// Edit › Copy (⌘C) when no label is being typed.
    @objc func copy(_ sender: Any?) { request(.copy) }
    /// File › Save (⌘S).
    @objc func saveEditedCapture(_ sender: Any?) { request(.save) }
    /// Edit › Undo (⌘Z) and Redo (⌘⇧Z) run the window's undo manager (ticket 69). NSWindow answers
    /// `undo:` and `redo:` itself, so these overrides live here to hold them while the editor finishes.
    @objc func undo(_ sender: Any?) { request(.undo) }
    @objc func redo(_ sender: Any?) { request(.redo) }
    /// Esc closes an unchanged editor; with edits it does nothing, and ⌘W asks.
    override func cancelOperation(_ sender: Any?) {
        if deselect?() == true { return }
        request(.closeUnchanged)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)): return canPerform?(.copy) ?? false
        case #selector(saveEditedCapture(_:)): return canPerform?(.save) ?? false
        case #selector(undo(_:)):
            menuItem.title = undoManager?.undoMenuItemTitle ?? "Undo"
            return canPerform?(.undo) ?? false
        case #selector(redo(_:)):
            menuItem.title = undoManager?.redoMenuItemTitle ?? "Redo"
            return canPerform?(.redo) ?? false
        default: return super.validateMenuItem(menuItem)
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

/// Shows the rendered document and hands each press and drag to the editor. The canvas is one
/// labelled element whose children are the marks (ticket 84); it takes Tab, the arrow keys and
/// Delete for the selected mark. What those do is `MarkEditor`'s, in the core.
@MainActor final class EditorCanvasView: NSView {
    enum DragGuide {
        case box, line, crop, conceal, soften, none
    }

    var rendered: NSImage? { didSet { needsDisplay = true } }
    var documentSize: CGSize { didSet { needsDisplay = true } }
    var guide: DragGuide = .box { didSet { needsDisplay = true } }
    /// A press at a point, with the hit tolerance in document points; true when it took hold of a mark.
    var onPress: ((CGPoint, Double) -> Bool)?
    /// The end of a press: start, end and tolerance.
    var onRelease: ((CGPoint, CGPoint, Double) -> Void)?
    /// A canvas key for marks; true when handled.
    var onMarkKey: ((MarkKey) -> Bool)?
    /// The selected mark's outline and handles, in canvas points.
    var selection: (box: MarkBox, handles: [(handle: MarkHandle, x: Double, y: Double)])? { didSet { needsDisplay = true } }
    /// Every mark's VoiceOver label and box, in canvas points, in Tab order.
    var accessibleMarks: [(label: String, box: MarkBox, selected: Bool)] = []
    /// The box of the label being typed, in canvas points (ticket 86).
    var typingBox: MarkBox? { didSet { needsDisplay = true } }
    /// Called when the canvas changes size, so the label being typed can follow the zoom.
    var onResize: (() -> Void)?
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var grabbing = false

    init(documentSize: CGSize) {
        self.documentSize = documentSize
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Capture canvas. Drag to hide pixels with a Solid redaction.")
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onResize?()
    }

    /// View points per document point.
    var zoom: CGFloat {
        guard documentSize.width > 0, documentSize.height > 0 else { return 0 }
        return min(bounds.width / documentSize.width, bounds.height / documentSize.height, 4)
    }

    private var imageRect: CGRect {
        let size = CGSize(width: documentSize.width * zoom, height: documentSize.height * zoom)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// Five view points, in document points.
    private var tolerance: Double { zoom > 0 ? Double(5 / zoom) : 5 }

    /// A box in canvas points, in this view's coordinates.
    func viewRect(_ box: MarkBox) -> CGRect {
        CGRect(x: imageRect.minX + box.x * zoom, y: imageRect.minY + box.y * zoom,
               width: box.width * zoom, height: box.height * zoom)
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let commandLike = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        if !commandLike, let key = MarkKey.action(characters: event.charactersIgnoringModifiers, shift: shift),
           onMarkKey?(key) == true { return }
        if !commandLike, event.charactersIgnoringModifiers == "\t" || event.charactersIgnoringModifiers == "\u{19}" {
            // Past the last mark, Tab leaves the canvas as usual.
            shift || event.charactersIgnoringModifiers == "\u{19}" ? window?.selectPreviousKeyView(self) : window?.selectNextKeyView(self)
            return
        }
        super.keyDown(with: event)
    }

    override func accessibilityChildren() -> [Any]? {
        guard let window else { return nil }
        return accessibleMarks.map { mark in
            let frame = window.convertToScreen(convert(viewRect(mark.box).insetBy(dx: -2, dy: -2), to: nil))
            let element = NSAccessibilityElement.element(withRole: .image, frame: frame, label: mark.label, parent: self)
            (element as? NSAccessibilityElement)?.setAccessibilitySelected(mark.selected)
            return element
        }
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
        drawSelection()
        if let typingBox {
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: viewRect(typingBox).insetBy(dx: -3, dy: -3))
            outline.lineWidth = 1
            outline.setLineDash([2, 2], count: 2, phase: 0)
            outline.stroke()
        }
        guard !grabbing, let start = dragStart, let current = dragCurrent else { return }
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
        case .none:
            break
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

    /// A blue outline with square handles; while the mark is dragged, the outline follows the pointer.
    private func drawSelection() {
        guard let selection else { return }
        var offset = CGPoint.zero
        if grabbing, let start = dragStart, let current = dragCurrent {
            offset = CGPoint(x: (current.x - start.x) * zoom, y: (current.y - start.y) * zoom)
        }
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(rect: viewRect(selection.box).insetBy(dx: -3, dy: -3).offsetBy(dx: offset.x, dy: offset.y))
        outline.lineWidth = 1
        outline.setLineDash([4, 3], count: 2, phase: 0)
        outline.stroke()
        for handle in selection.handles {
            let centre = CGPoint(x: imageRect.minX + handle.x * zoom, y: imageRect.minY + handle.y * zoom)
            let square = NSBezierPath(rect: CGRect(x: centre.x - 4, y: centre.y - 4, width: 8, height: 8))
            NSColor.white.setFill()
            square.fill()
            NSColor.controlAccentColor.setStroke()
            square.lineWidth = 1.5
            square.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragStart = documentPoint(event)
        dragCurrent = dragStart
        grabbing = dragStart.map { onPress?($0, tolerance) ?? false } ?? false
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = documentPoint(event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let start = dragStart, end = documentPoint(event)
        dragStart = nil
        dragCurrent = nil
        grabbing = false
        if let start, let end { onRelease?(start, end, tolerance) }
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
    /// The edits and their undo manager, which the window returns for Edit › Undo and Redo.
    private let document: UndoableEdits
    /// The selected mark and every change to marks (ticket 84).
    private let marks: MarkEditor
    private var grab: MarkEditor.Grab?
    private let widthPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    /// The Text tool's contextual controls (ticket 86): size and style of new labels and the selected one.
    private let labelSizePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let labelStylePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    /// The label being typed on the canvas, and the text view that takes the typing. The view only
    /// holds the caret and selection; its text is clear, and the canvas shows the rendered label.
    private var labelSession: LabelSession?
    private var labelView: NSTextView?
    private let stylePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private var edits: DocumentEdits { document.edits }
    private let textTool = TextTool()
    private let redactionTool = SolidRedactionTool()
    /// The Solid redaction palette (ticket 88): one swatch per colour, for the tool and a selected redaction.
    private var swatchButtons: [NSButton] = []
    private let swatchStack = NSStackView()
    /// The style bar (ticket 92): the style controls that apply to the selected mark or the active
    /// tool, in the content area so none of them falls into the toolbar's overflow menu.
    private let styleBar = NSStackView()
    private let hintField = NSTextField(labelWithString: "")
    private let tools: [any EditorTool]
    /// Solid Redaction; the Select tool is first in the toolbar.
    private var activeTool: Int = 1
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
        document = UndoableEdits(edits)
        marks = MarkEditor(document)
        self.finish = finish
        pixelSize = CGSize(width: preview.captureWidth, height: preview.captureHeight)
        tools = [SelectTool(), redactionTool, CropTool(), ArrowTool(), LineTool(), RectangleTool(), textTool, BlurTool(),
                 MagnifyTool()]
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
        document.onChange = { [weak self] in self?.refresh() }
        marks.onSelectionChange = { [weak self] in self?.selectionChanged() }

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
        for size in LabelFormat.sizes {
            labelSizePopUp.addItem(withTitle: "\(Int(size)) pt")
            labelSizePopUp.lastItem?.representedObject = size
        }
        labelSizePopUp.controlSize = .small
        labelSizePopUp.target = self
        labelSizePopUp.action = #selector(changeLabelSize(_:))
        labelSizePopUp.setAccessibilityLabel("Label size")
        labelSizePopUp.toolTip = "Size of new labels, and of the selected one"
        labelSizePopUp.sizeToFit()
        for style in LabelStyle.allCases {
            labelStylePopUp.addItem(withTitle: style.title)
            labelStylePopUp.lastItem?.representedObject = style.rawValue
            labelStylePopUp.lastItem?.setAccessibilityLabel("\(style.title) label")
        }
        labelStylePopUp.controlSize = .small
        labelStylePopUp.target = self
        labelStylePopUp.action = #selector(changeLabelStyle(_:))
        labelStylePopUp.setAccessibilityLabel("Label style")
        labelStylePopUp.toolTip = "Label style: Standard, Outlined or Box"
        labelStylePopUp.sizeToFit()
        // The drawing tool's contextual controls (ticket 85): line width and arrow style for new marks,
        // and for the selected mark when there is one. Colour arrives with the palette (ticket 88).
        for width in DocumentAnnotation.lineWidths {
            widthPopUp.addItem(withTitle: "\(Int(width)) pt")
            widthPopUp.lastItem?.representedObject = width
        }
        widthPopUp.controlSize = .small
        widthPopUp.target = self
        widthPopUp.action = #selector(changeWidth(_:))
        widthPopUp.setAccessibilityLabel("Line width")
        widthPopUp.toolTip = "Line width of new arrows, lines and shapes, and of the selected one"
        widthPopUp.sizeToFit()
        for style in ArrowStyle.arrowStyles {
            stylePopUp.addItem(withTitle: style.title)
            stylePopUp.lastItem?.representedObject = style.rawValue
            stylePopUp.lastItem?.setAccessibilityLabel("\(style.title) arrow")
        }
        stylePopUp.controlSize = .small
        stylePopUp.target = self
        stylePopUp.action = #selector(changeStyle(_:))
        stylePopUp.setAccessibilityLabel("Arrow style")
        stylePopUp.toolTip = "Arrow style: Standard, Curved (drag the middle handle to bend it) or Double"
        stylePopUp.sizeToFit()
        for (index, choice) in SolidRedaction.palette.enumerated() {
            let button = NSButton(image: Self.swatch(choice.pixel), target: self, action: #selector(chooseRedactionColour(_:)))
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .texturedRounded
            button.controlSize = .small
            button.tag = index
            button.setAccessibilityLabel("Redaction colour: \(choice.name)")
            button.toolTip = "Redaction colour: \(choice.name)"
            swatchButtons.append(button)
            swatchStack.addArrangedSubview(button)
        }
        swatchStack.orientation = .horizontal
        swatchStack.spacing = 2
        swatchStack.setAccessibilityElement(true)
        swatchStack.setAccessibilityRole(.group)
        swatchStack.setAccessibilityLabel("Redaction colour")
        for control in [swatchStack, stylePopUp, widthPopUp, labelSizePopUp, labelStylePopUp] {
            styleBar.addArrangedSubview(control)
        }
        styleBar.orientation = .horizontal
        styleBar.alignment = .centerY
        styleBar.spacing = 12
        styleBar.detachesHiddenViews = true
        styleBar.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        styleBar.setAccessibilityElement(true)
        styleBar.setAccessibilityRole(.group)
        styleBar.setAccessibilityLabel("Style")
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
        window.deselect = { [weak self] in self?.marks.deselect() ?? false }
        let probe = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 800, height: 400))
        let chromeAbove = probe.height - 400
        let hintHeight: CGFloat = 44
        let barHeight = EditorWindowLayout.actionBarHeight
        let styleHeight = EditorWindowLayout.styleBarHeight
        var size = EditorWindowLayout.contentSize(document: documentSize, visible: visible.size,
            chrome: EditorWindowLayout.Chrome(toolbarHeight: styleHeight + hintHeight + barHeight, titlebarHeight: chromeAbove))
        size.width = max(size.width, min(EditorWindowLayout.defaultContentWidth, visible.width))
        window.contentMinSize = CGSize(width: min(EditorWindowLayout.minimumContentWidth, visible.width),
                                       height: min(styleHeight + hintHeight + barHeight + 80, size.height))
        window.maxSize = visible.size
        let content = NSView(frame: CGRect(origin: .zero, size: size))
        let bar = EditorActionBar(dragHandle: dragWell, copy: copyButton, save: saveButton, done: doneButton)
        bar.frame = CGRect(x: 0, y: 0, width: size.width, height: barHeight)
        bar.autoresizingMask = [.width, .maxYMargin]
        canvas.frame = CGRect(x: 0, y: barHeight, width: size.width,
                              height: max(1, size.height - styleHeight - hintHeight - barHeight))
        canvas.autoresizingMask = [.width, .height]
        canvas.onPress = { [weak self] point, tolerance in self?.press(at: point, tolerance: tolerance) ?? false }
        canvas.onRelease = { [weak self] start, end, tolerance in self?.release(from: start, to: end, tolerance: tolerance) }
        canvas.onMarkKey = { [weak self] key in self?.markKey(key) ?? false }
        canvas.onResize = { [weak self] in self?.placeLabelView() }
        styleBar.frame = CGRect(x: 0, y: size.height - styleHeight, width: size.width, height: styleHeight)
        styleBar.autoresizingMask = [.width, .minYMargin]
        hintField.frame = CGRect(x: 12, y: size.height - styleHeight - hintHeight + 6, width: size.width - 24, height: hintHeight - 10)
        hintField.autoresizingMask = [.width, .minYMargin]
        content.addSubview(canvas)
        content.addSubview(styleBar)
        content.addSubview(hintField)
        content.addSubview(bar)
        window.contentView = content
        window.setContentSize(size)
        window.initialFirstResponder = toolButtons.first
        window.autorecalculatesKeyViewLoop = true
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
        endLabel()
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

    private var unchanged: Bool { document.isUnchanged }

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
        if let session = labelSession, !session.isCurrent || finishing {
            // An undo replaced the typing, or the editor is finishing: typing ends.
            endLabel()
            return
        }
        placeLabelView()
        // The style bar shows the selected mark's controls, or the active tool's (ticket 92).
        let shown = Set(StyleBar.controls(tool: tools[activeTool].kind,
                                          selection: labelSession == nil ? marks.selection : nil, in: edits))
        swatchStack.isHidden = !shown.contains(.redactionColour)
        stylePopUp.isHidden = !shown.contains(.arrowStyle)
        widthPopUp.isHidden = !shown.contains(.lineWidth)
        labelSizePopUp.isHidden = !shown.contains(.labelSize)
        labelStylePopUp.isHidden = !shown.contains(.labelStyle)
        let labelFormat = labelSession?.format ?? marks.selectionLabel ?? (tools[activeTool] is TextTool ? textTool.format : nil)
        labelSizePopUp.isEnabled = !finishing && labelFormat != nil
        labelStylePopUp.isEnabled = !finishing && labelFormat != nil
        if let labelFormat {
            if let index = labelSizePopUp.itemArray.firstIndex(where: { $0.representedObject as? Double == labelFormat.size }) {
                labelSizePopUp.selectItem(at: index)
            }
            if let index = labelStylePopUp.itemArray.firstIndex(where: { $0.representedObject as? String == labelFormat.style.rawValue }) {
                labelStylePopUp.selectItem(at: index)
            }
        }
        canvas.selection = marks.selectionOutline
        canvas.accessibleMarks = marks.accessibleMarks.map { ($0.label, $0.box, $0.mark == marks.selection) }
        let fill = marks.selectionFill
        let shownFill = fill ?? redactionTool.colour
        for button in swatchButtons {
            button.isEnabled = !finishing && (fill != nil || tools[activeTool] is SolidRedactionTool)
            button.state = SolidRedaction.palette[button.tag].pixel == shownFill ? .on : .off
        }
        // The selected mark's width and style, or else the active tool's.
        let widthTool = tools[activeTool] as? LineWidthTool
        let width = marks.selectionWidth ?? widthTool?.width
        widthPopUp.isEnabled = !finishing && width != nil
        if let width, let index = widthPopUp.itemArray.firstIndex(where: { $0.representedObject as? Double == width }) {
            widthPopUp.selectItem(at: index)
        }
        let arrowTool = tools[activeTool] as? ArrowTool
        let style: ArrowStyle?
        if let selected = marks.selectionStyle {
            style = selected == .line ? nil : selected
        } else {
            style = arrowTool is LineTool ? nil : arrowTool?.style
        }
        stylePopUp.isEnabled = !finishing && style != nil
        if let style, let index = stylePopUp.itemArray.firstIndex(where: { $0.representedObject as? String == style.rawValue }) {
            stylePopUp.selectItem(at: index)
        }
        undoButton.isEnabled = canPerform(.undo)
        undoButton.toolTip = "\(document.undoManager.undoMenuItemTitle) (⌘Z)"
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
        case is SelectTool:
            canvas.guide = .box
            hintField.stringValue = "Click a mark to select it. Drag it to move, drag a handle to resize, Delete removes it. Tab steps through marks; arrow keys move."
            canvas.setAccessibilityLabel("Capture canvas. Click a mark to select it. Tab steps through marks.")
        case is SolidRedactionTool:
            canvas.guide = .conceal
            let colour = redactionTool.colourName
            hintField.stringValue = "Drag a box. It is painted solid \(colour.lowercased()) and stays hidden under blur."
            canvas.setAccessibilityLabel("Capture canvas. Drag to hide pixels with a Solid redaction in \(colour).")
        case is CropTool:
            canvas.guide = .crop
            hintField.stringValue = "Drag the area to keep. Everything outside it is removed."
            canvas.setAccessibilityLabel("Capture canvas. Drag the area to keep.")
        case is LineTool:
            canvas.guide = .line
            hintField.stringValue = "Drag from one end to the other. Drawing does not hide pixels."
            canvas.setAccessibilityLabel("Capture canvas. Drag to draw a line. Drawing does not hide pixels.")
        case let arrow as ArrowTool:
            canvas.guide = .line
            hintField.stringValue = arrow.style == .curved
                ? "Drag from the tail to the point, then drag the middle handle to bend it. Drawing does not hide pixels."
                : "Drag from the tail to the point. Drawing does not hide pixels."
            canvas.setAccessibilityLabel("Capture canvas. Drag to draw. Drawing does not hide pixels.")
        case is RectangleTool:
            canvas.guide = .box
            hintField.stringValue = "Drag a rectangle outline. Drawing does not hide pixels."
            canvas.setAccessibilityLabel("Capture canvas. Drag to draw. Drawing does not hide pixels.")
        case is TextTool:
            canvas.guide = .none
            hintField.stringValue = labelSession == nil
                ? "Click where the label should start, then type. Click a label to edit it; drag its side handle to wrap it. Labels do not hide pixels."
                : "Type the label. Return or a click elsewhere ends it; Esc cancels an empty label. Labels do not hide pixels."
            canvas.setAccessibilityLabel("Capture canvas. Click to type a label. Labels do not hide pixels.")
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

    /// A press takes hold of the selected mark (or, with the Select tool, any mark); otherwise the
    /// active tool draws on release.
    private func press(at point: CGPoint, tolerance: Double) -> Bool {
        guard !finishing else { return false }
        grab = marks.press(atX: point.x, y: point.y, tolerance: tolerance, anyMark: tools[activeTool] is SelectTool)
        return grab != nil
    }

    /// Releasing a held mark moves or resizes it. A click selects the mark under it (or deselects;
    /// the Text tool then places its label); a drag draws with the active tool.
    private func release(from start: CGPoint, to end: CGPoint, tolerance: Double) {
        guard !finishing else { return }
        let isClick = hypot(end.x - start.x, end.y - start.y) <= tolerance / 2
        if let held = grab {
            grab = nil
            let changed = marks.release(held, fromX: start.x, fromY: start.y, toX: end.x, toY: end.y, slop: tolerance / 2)
            // The Text tool edits a label clicked while it is selected.
            if !changed, isClick, held.handle == nil, tools[activeTool] is TextTool,
               let session = LabelSession(document: document, editing: held.mark) {
                beginLabel(session)
            }
            return
        }
        if tools[activeTool] is TextTool {
            // A click on a label edits it; a click on another mark selects it; anywhere else, or at
            // the start of a drag, a new label starts.
            if isClick, let label = marks.label(atX: end.x, y: end.y, tolerance: tolerance),
               let session = LabelSession(document: document, editing: label) {
                beginLabel(session)
                return
            }
            if isClick, marks.click(atX: end.x, y: end.y, tolerance: tolerance) { return }
            let origin = (x: edits.crop?.x ?? 0, y: edits.crop?.y ?? 0)
            beginLabel(LabelSession(document: document, x: start.x + origin.x, y: start.y + origin.y, format: textTool.format))
            return
        }
        if isClick {
            marks.click(atX: end.x, y: end.y, tolerance: tolerance)
            return
        }
        marks.deselect()
        var next = edits
        guard tools[activeTool].applyDrag(from: start, to: end, to: &next) else { return }
        document.apply(next)
    }

    private func markKey(_ key: MarkKey) -> Bool {
        guard !finishing else { return false }
        switch key {
        case .next: return marks.selectNext()
        case .previous: return marks.selectNext(backward: true)
        case .delete: return marks.deleteSelection()
        case let .nudge(dx, dy): return marks.nudge(dx: dx, dy: dy)
        }
    }

    private func selectionChanged() {
        refresh()
        NSAccessibility.post(element: canvas, notification: .selectedChildrenChanged)
        let edits = edits
        let announcement = marks.selection.map { "Selected: \(edits.accessibilityLabel(for: $0))" } ?? "No mark selected"
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: announcement,
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    /// A palette colour becomes the tool's fill for new redactions and recolours a selected one.
    @objc private func chooseRedactionColour(_ sender: NSButton) {
        guard !finishing, SolidRedaction.palette.indices.contains(sender.tag) else { return }
        let choice = SolidRedaction.palette[sender.tag]
        redactionTool.colour = choice.pixel
        if marks.selectionFill != nil { marks.recolourSelection(choice.pixel) }
        refresh()
    }

    /// A small opaque square of `pixel`, outlined so white and black both read on any bezel.
    private static func swatch(_ pixel: RGBAPixel) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let square = NSBezierPath(rect: rect.insetBy(dx: 1.5, dy: 1.5))
            NSColor(srgbRed: CGFloat(pixel.red) / 255, green: CGFloat(pixel.green) / 255,
                    blue: CGFloat(pixel.blue) / 255, alpha: 1).setFill()
            square.fill()
            NSColor.secondaryLabelColor.setStroke()
            square.lineWidth = 1
            square.stroke()
            return true
        }
    }

    @objc private func changeWidth(_ sender: NSPopUpButton) {
        guard !finishing, let width = sender.selectedItem?.representedObject as? Double else { return }
        (tools[activeTool] as? LineWidthTool)?.width = width
        if !marks.rewidthSelection(width) { refresh() }
    }

    /// A size from the Text tool's menu: for new labels, the label being typed, or the selected label.
    @objc private func changeLabelSize(_ sender: NSPopUpButton) {
        guard !finishing, let size = sender.selectedItem?.representedObject as? Double else { return }
        relabel { $0.with(size: size) }
    }

    @objc private func changeLabelStyle(_ sender: NSPopUpButton) {
        guard !finishing, let raw = sender.selectedItem?.representedObject as? String,
              let style = LabelStyle(rawValue: raw) else { return }
        relabel { $0.with(style: style) }
    }

    private func relabel(_ change: (LabelFormat) -> LabelFormat?) {
        if tools[activeTool] is TextTool, let format = change(textTool.format) { textTool.format = format }
        if let session = labelSession {
            if let format = change(session.format) { session.restyle(format) }
            if let labelView { window.makeFirstResponder(labelView) }
        } else if let selected = marks.selectionLabel, let format = change(selected) {
            marks.relabelSelection(format)
        }
        refresh()
    }

    /// Starts typing a label: a clear text view over it takes the keys, with the caret, and every
    /// change goes into the edits through the session, as one undo step (decision 77).
    private func beginLabel(_ session: LabelSession) {
        endLabel()
        marks.deselect()
        labelSession = session
        let view = NSTextView(frame: .zero)
        view.string = session.characters
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = false
        view.drawsBackground = false
        view.textColor = .clear
        view.insertionPointColor = .controlAccentColor
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        // Exactly the typed characters: no smart quotes, dashes, replacements or corrections.
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isAutomaticTextCompletionEnabled = false
        view.setAccessibilityLabel("Label text. Return ends the label.")
        view.delegate = self
        labelView = view
        canvas.addSubview(view)
        placeLabelView()
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: (session.characters as NSString).length, length: 0))
        refresh()
    }

    /// Ends typing. The session already wrote the label (or, if it is blank, nothing), so this only
    /// removes the text view and selects the label, ready for its width handle and menus.
    private func endLabel() {
        guard let session = labelSession else { return }
        labelSession = nil
        let view = labelView
        labelView = nil
        view?.delegate = nil
        if let view, window.firstResponder === view { window.makeFirstResponder(canvas) }
        view?.removeFromSuperview()
        canvas.typingBox = nil
        if session.isCurrent, let mark = session.mark { marks.select(mark) }
        refresh()
    }

    /// Puts the text view over the label being typed, at the canvas's zoom, and outlines its box.
    private func placeLabelView() {
        guard let session = labelSession, let view = labelView else { return }
        let origin = (x: edits.crop?.x ?? 0, y: edits.crop?.y ?? 0)
        let box = session.box
        canvas.typingBox = MarkBox(x: box.x - origin.x, y: box.y - origin.y, width: box.width, height: box.height)
        let zoom = canvas.zoom
        let layout = LabelLayout(characters: session.characters, format: session.format)
        let width = (session.format.wrapWidth ?? max(layout.textWidth, session.format.size)) * zoom
        let text = MarkBox(x: session.x - origin.x, y: session.y - origin.y, width: 0, height: 0)
        let corner = canvas.viewRect(text).origin
        view.font = NSFont(name: LabelLayout.fontName, size: max(1, session.format.size * zoom))
        view.textContainer?.containerSize = NSSize(width: session.format.wrapWidth == nil ? 1e6 : width,
                                                   height: 1e6)
        view.frame = CGRect(x: corner.x, y: corner.y, width: width + 4, height: max(1, layout.textHeight * zoom) + 2)
    }

    @objc private func changeStyle(_ sender: NSPopUpButton) {
        guard !finishing, let raw = sender.selectedItem?.representedObject as? String,
              let style = ArrowStyle(rawValue: raw) else { return }
        if let arrow = tools[activeTool] as? ArrowTool, !(arrow is LineTool) { arrow.style = style }
        if !marks.restyleSelection(style) { refresh() }
    }

    @objc private func selectTool(_ sender: NSButton) {
        guard !finishing else { return }
        endLabel()
        activeTool = sender.tag
        refresh()
    }

    @objc private func undo() {
        guard canPerform(.undo) else { return }
        document.undoManager.undo()
    }

    private func redo() {
        guard canPerform(.redo) else { return }
        document.undoManager.redo()
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
        case .undo: return document.undoManager.canUndo
        case .redo: return document.undoManager.canRedo
        case .closeUnchanged: return unchanged
        }
    }

    private func perform(_ action: EditorAction) {
        switch action {
        case .done: done()
        case .copy: copyRendered()
        case .save: saveRendered()
        case .undo: undo()
        case .redo: redo()
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
        endLabel()
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

    /// Edit › Undo and Redo, ⌘Z and ⌘⇧Z, and label typing all use the edits' undo manager.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        document.undoManager
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
            + [.flexibleSpace, .init("undo"), .init("close")]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier.rawValue {
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

extension EditorWindow: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let view = notification.object as? NSTextView, view === labelView else { return }
        labelSession?.type(view.string)
    }

    /// Leaving the text view (a click on the canvas or elsewhere) ends typing, after the click.
    func textDidEndEditing(_ notification: Notification) {
        guard let view = notification.object as? NSTextView else { return }
        Task { @MainActor [weak self] in
            guard let self, self.labelView === view else { return }
            self.endLabel()
        }
    }

    /// Return and Tab end the label without meaning Done; Esc ends it too, which cancels an empty
    /// label (the session holds nothing for blank text). Option-Return types a line break.
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)),
             #selector(NSResponder.insertBacktab(_:)), #selector(NSResponder.cancelOperation(_:)):
            endLabel()
            return true
        default:
            return false
        }
    }
}
