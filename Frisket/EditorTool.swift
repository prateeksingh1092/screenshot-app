import Foundation
import FrisketCore

/// A canvas tool. The editor lists every tool in its palette and hands the active one
/// each completed canvas drag, in document points. Later tools (crop, arrows, shapes,
/// text, blur) add conformers here; the document and renderer stay the only pixel path.
enum EditorToolRole: Equatable {
    case conceal, frame, draw, select
}

@MainActor protocol EditorTool: AnyObject {
    var title: String { get }
    var accessibilityLabel: String { get }
    var keyEquivalent: String { get }
    var symbolName: String { get }
    var role: EditorToolRole { get }
    /// Applies a drag from `start` to `end`; returns false when the drag changes nothing.
    func applyDrag(from start: CGPoint, to end: CGPoint, to edits: inout DocumentEdits) -> Bool
}

/// A tool that draws with a line width chosen in its contextual controls (ticket 85).
@MainActor protocol LineWidthTool: EditorTool {
    var width: Double { get set }
}

/// Selects marks (ticket 84): a press on any mark takes hold of it. It draws nothing.
@MainActor final class SelectTool: EditorTool {
    let title = "Select"
    let accessibilityLabel = "Select tool. Click a mark to move, resize, restyle or delete it."
    let keyEquivalent = "v"
    let symbolName = "cursorarrow"
    let role = EditorToolRole.select

    func applyDrag(from start: CGPoint, to end: CGPoint, to edits: inout DocumentEdits) -> Bool { false }
}

@MainActor final class SolidRedactionTool: EditorTool {
    let title = "Solid Redaction"
    let accessibilityLabel = "Solid redaction. Hides pixels with an opaque colour, black by default."
    let keyEquivalent = "r"
    let symbolName = "square.fill"
    let role = EditorToolRole.conceal
    /// The fill for new redactions: a palette colour, black until the user picks another (decision 61).
    var colour = SolidRedaction.fill
    var colourName: String { SolidRedaction.palette.first { $0.pixel == colour }?.name ?? "Black" }

    func applyDrag(from start: CGPoint, to end: CGPoint, to edits: inout DocumentEdits) -> Bool {
        let originX = edits.crop?.x ?? 0
        let originY = edits.crop?.y ?? 0
        guard let redaction = SolidRedaction(x: min(start.x, end.x) + originX, y: min(start.y, end.y) + originY,
                                             width: abs(end.x - start.x), height: abs(end.y - start.y),
                                             colour: colour) else { return false }
        edits.redactions.append(redaction)
        return true
    }
}

@MainActor final class CropTool: EditorTool {
    let title = "Crop"
    let accessibilityLabel = "Crop tool"
    let keyEquivalent = "c"
    let symbolName = "crop"
    let role = EditorToolRole.frame

    func applyDrag(from start: CGPoint, to end: CGPoint, to edits: inout DocumentEdits) -> Bool {
        let originX = edits.crop?.x ?? 0
        let originY = edits.crop?.y ?? 0
        guard let crop = DocumentCrop(x: min(start.x, end.x) + originX, y: min(start.y, end.y) + originY,
                                      width: abs(end.x - start.x), height: abs(end.y - start.y)) else { return false }
        edits.crop = crop
        return true
    }
}

@MainActor final class RectangleTool: LineWidthTool {
    var width = DocumentAnnotation.defaultWidth
    let title = "Shape"
    let accessibilityLabel = "Rectangle shape tool. Drawing does not hide pixels."
    let keyEquivalent = "s"
    let symbolName = "rectangle"
    let role = EditorToolRole.draw

    func applyDrag(from start: CGPoint, to end: CGPoint, to edits: inout DocumentEdits) -> Bool {
        let originX = edits.crop?.x ?? 0
        let originY = edits.crop?.y ?? 0
        guard let annotation = DocumentAnnotation(.rectangle(x: min(start.x, end.x) + originX, y: min(start.y, end.y) + originY,
                                                             width: abs(end.x - start.x), height: abs(end.y - start.y)),
                                                width: width) else { return false }
        edits.annotations.append(annotation)
        return true
    }
}

/// Arrows in the style chosen in its style menu (ticket 85): Standard, Curved or Double.
@MainActor class ArrowTool: LineWidthTool {
    var width = DocumentAnnotation.defaultWidth
    var style: ArrowStyle
    var title: String { "Arrow" }
    var accessibilityLabel: String { "Arrow tool. Drawing does not hide pixels." }
    var keyEquivalent: String { "a" }
    var symbolName: String { "arrow.up.right" }
    let role = EditorToolRole.draw

    init(style: ArrowStyle = .standard) {
        self.style = style
    }

    func applyDrag(from start: CGPoint, to end: CGPoint, to edits: inout DocumentEdits) -> Bool {
        let originX = edits.crop?.x ?? 0
        let originY = edits.crop?.y ?? 0
        guard let annotation = DocumentAnnotation(.arrow(x0: start.x + originX, y0: start.y + originY,
                                                         x1: end.x + originX, y1: end.y + originY),
                                                  width: width, style: style) else { return false }
        edits.annotations.append(annotation)
        return true
    }
}

/// The plain Line tool (ticket 85): an arrow-kind mark with no head.
@MainActor final class LineTool: ArrowTool {
    init() {
        super.init(style: .line)
    }
    override var title: String { "Line" }
    override var accessibilityLabel: String { "Line tool. Drawing does not hide pixels." }
    override var keyEquivalent: String { "l" }
    override var symbolName: String { "line.diagonal" }
}

/// Labels typed on the image (ticket 86): a click starts a label there, typed on the canvas. Its
/// size and style menus set `format` for new labels.
@MainActor final class TextTool: EditorTool {
    let title = "Text"
    let accessibilityLabel = "Text label tool. Click and type on the image. Labels do not hide pixels."
    let keyEquivalent = "t"
    let symbolName = "textformat"
    let role = EditorToolRole.draw
    var format = LabelFormat.standard

    /// The editor starts a typing session instead; a drag draws nothing.
    func applyDrag(from start: CGPoint, to end: CGPoint, to edits: inout DocumentEdits) -> Bool { false }
}

@MainActor final class BlurTool: EditorTool {
    let title = "Blur"
    let accessibilityLabel = "Blur. Softens pixels and does not hide them. Use Solid Redaction to conceal."
    let keyEquivalent = "b"
    let symbolName = "circle.lefthalf.filled"
    let role = EditorToolRole.draw

    func applyDrag(from start: CGPoint, to end: CGPoint, to edits: inout DocumentEdits) -> Bool {
        let originX = edits.crop?.x ?? 0
        let originY = edits.crop?.y ?? 0
        guard let effect = DocumentEffect(.blur(x: min(start.x, end.x) + originX, y: min(start.y, end.y) + originY,
                                                width: abs(end.x - start.x), height: abs(end.y - start.y))) else { return false }
        edits.effects.append(effect)
        return true
    }
}

@MainActor final class MagnifyTool: EditorTool {
    let title = "Magnify"
    let accessibilityLabel = "Magnify. Doubles pixels and does not hide them. Use Solid Redaction to conceal."
    let keyEquivalent = "m"
    let symbolName = "plus.magnifyingglass"
    let role = EditorToolRole.draw

    func applyDrag(from start: CGPoint, to end: CGPoint, to edits: inout DocumentEdits) -> Bool {
        let originX = edits.crop?.x ?? 0
        let originY = edits.crop?.y ?? 0
        guard let effect = DocumentEffect(.magnify(x: min(start.x, end.x) + originX, y: min(start.y, end.y) + originY,
                                                   width: abs(end.x - start.x), height: abs(end.y - start.y))) else { return false }
        edits.effects.append(effect)
        return true
    }
}
