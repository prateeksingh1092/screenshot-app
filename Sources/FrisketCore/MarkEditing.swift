import CoreGraphics
import Foundation

/// One mark in the editor's edits (ticket 84): a Solid redaction, a Blur or Magnify box, or an
/// annotation, by its index in its list. Crop is not a mark.
public enum MarkReference: Hashable, Sendable {
    case redaction(Int)
    case effect(Int)
    case annotation(Int)
}

/// A handle on a selected mark. Boxes have four corners; an arrow has its tail and tip, and a Curved
/// arrow also its middle, `bend` (ticket 85). A label has one on its right side, `trailing`, that
/// sets the width its text wraps at (ticket 86).
public enum MarkHandle: Hashable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight, tail, tip, bend, trailing
}

/// A change to one mark. Each is one undo step.
public enum MarkChange: Equatable, Sendable {
    case move(dx: Double, dy: Double)
    /// Drags `handle` to the point `(x, y)`, in document points of the uncropped capture.
    case resize(MarkHandle, x: Double, y: Double)
    case delete
    /// A new colour: an annotation's ink, or a Solid redaction's fill (always alpha 255, decision 61).
    case recolour(RGBAPixel)
    /// A new line width in document points, for shapes and arrows.
    case rewidth(Double)
    /// A new style for an arrow or line (ticket 85).
    case restyle(ArrowStyle)
    /// A new style, size or wrap width for a label (ticket 86).
    case relabel(LabelFormat)
    /// New characters for a label; blank text is refused (delete the label instead).
    case retext(String)
}

/// A rectangle in document points.
public struct MarkBox: Equatable, Sendable {
    public let x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    func contains(_ px: Double, _ py: Double, outset: Double) -> Bool {
        px >= x - outset && px <= x + width + outset && py >= y - outset && py <= y + height + outset
    }
}

extension DocumentEdits {
    /// Every mark in paint order: redactions, effects, then annotations. Tab walks this order.
    public var marks: [MarkReference] {
        redactions.indices.map(MarkReference.redaction) + effects.indices.map(MarkReference.effect)
            + annotations.indices.map(MarkReference.annotation)
    }

    public func contains(_ mark: MarkReference) -> Bool {
        switch mark {
        case .redaction(let index): redactions.indices.contains(index)
        case .effect(let index): effects.indices.contains(index)
        case .annotation(let index): annotations.indices.contains(index)
        }
    }

    /// The mark's bounding box in document points of the uncropped capture.
    public func bounds(of mark: MarkReference) -> MarkBox? {
        guard contains(mark) else { return nil }
        switch mark {
        case .redaction(let index):
            let r = redactions[index]
            return MarkBox(x: r.x, y: r.y, width: r.width, height: r.height)
        case .effect(let index):
            let r = effects[index].rectangle
            return MarkBox(x: r.x, y: r.y, width: r.width, height: r.height)
        case .annotation(let index):
            switch annotations[index].kind {
            case let .rectangle(x, y, width, height):
                return MarkBox(x: x, y: y, width: width, height: height)
            case .arrow:
                let spine = spine(of: annotations[index])
                let xs = spine.map(\.x), ys = spine.map(\.y)
                let minX = xs.min() ?? 0, minY = ys.min() ?? 0
                return MarkBox(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
            case let .text(x, y, characters):
                let box = LabelLayout(characters: characters, format: annotations[index].label).bounds
                return MarkBox(x: x + box.x, y: y + box.y, width: box.width, height: box.height)
            }
        }
    }

    /// The selected mark's handles and where they are, in document points.
    public func handles(of mark: MarkReference) -> [(handle: MarkHandle, x: Double, y: Double)] {
        guard contains(mark) else { return [] }
        if case .annotation(let index) = mark {
            switch annotations[index].kind {
            case let .arrow(x0, y0, x1, y1):
                let annotation = annotations[index]
                guard annotation.style == .curved else { return [(.tail, x0, y0), (.tip, x1, y1)] }
                let middle = annotation.bend.handle(tail: CGPoint(x: x0, y: y0), tip: CGPoint(x: x1, y: y1))
                return [(.tail, x0, y0), (.bend, middle.x, middle.y), (.tip, x1, y1)]
            case .text:
                guard let box = bounds(of: mark) else { return [] }
                return [(.trailing, box.x + box.width, box.y + box.height / 2)]
            case .rectangle: break
            }
        }
        guard let box = bounds(of: mark) else { return [] }
        return [(.topLeft, box.x, box.y), (.topRight, box.x + box.width, box.y),
                (.bottomLeft, box.x, box.y + box.height), (.bottomRight, box.x + box.width, box.y + box.height)]
    }

    /// The topmost mark under `(x, y)`, within `tolerance` document points. Shapes are hit on their
    /// outline and arrows on their line, so a click inside an outline reaches what lies under it;
    /// redactions, effects and labels are hit anywhere inside.
    public func mark(atX x: Double, y: Double, tolerance: Double) -> MarkReference? {
        marks.reversed().first { hits($0, x, y, tolerance) }
    }

    /// The handle of `mark` nearest `(x, y)`, if one is within `tolerance`.
    public func handle(of mark: MarkReference, atX x: Double, y: Double, tolerance: Double) -> MarkHandle? {
        handles(of: mark)
            .map { (handle: $0.handle, distance: hypot($0.x - x, $0.y - y)) }
            .filter { $0.distance <= tolerance }
            .min { $0.distance < $1.distance }?.handle
    }

    func hits(_ mark: MarkReference, _ px: Double, _ py: Double, _ tolerance: Double) -> Bool {
        guard let box = bounds(of: mark) else { return false }
        guard case .annotation(let index) = mark else { return box.contains(px, py, outset: tolerance) }
        let annotation = annotations[index]
        switch annotation.kind {
        case .text:
            return box.contains(px, py, outset: tolerance)
        case .rectangle:
            // The stroke lies inside the box.
            let inner = tolerance + annotation.width
            let inside = MarkBox(x: box.x + inner, y: box.y + inner, width: box.width - 2 * inner, height: box.height - 2 * inner)
            return box.contains(px, py, outset: tolerance)
                && !(inside.width > 0 && inside.height > 0 && inside.contains(px, py, outset: 0))
        case .arrow:
            let spine = spine(of: annotation)
            return zip(spine, spine.dropFirst()).contains { a, b in
                let dx = b.x - a.x, dy = b.y - a.y, squared = dx * dx + dy * dy
                let t = squared > 0 ? max(0, min(1, ((px - a.x) * dx + (py - a.y) * dy) / squared)) : 0
                return hypot(a.x + t * dx - px, a.y + t * dy - py) <= tolerance + annotation.width / 2
            }
        }
    }

    /// An arrow's centre line in document points: straight, or sampled along its curve.
    private func spine(of annotation: DocumentAnnotation) -> [CGPoint] {
        guard case let .arrow(x0, y0, x1, y1) = annotation.kind else { return [] }
        return ArrowGeometry.spine(style: annotation.style, tail: CGPoint(x: x0, y: y0), tip: CGPoint(x: x1, y: y1),
                                   bend: annotation.bend)
    }

    /// These edits with `change` made to `mark`, or nil when the change does not apply to it
    /// (a label has no width) or would leave an empty or invalid mark.
    public func applying(_ change: MarkChange, to mark: MarkReference) -> DocumentEdits? {
        guard contains(mark) else { return nil }
        var next = self
        switch mark {
        case .redaction(let index):
            let old = redactions[index]
            if change == .delete { next.redactions.remove(at: index); return next }
            let colour: RGBAPixel
            if case .recolour(let chosen) = change { colour = chosen } else { colour = old.colour }
            if case .rewidth = change { return nil }
            if case .restyle = change { return nil }
            if case .relabel = change { return nil }
            guard let box = Self.box(MarkBox(x: old.x, y: old.y, width: old.width, height: old.height), change),
                  let redaction = SolidRedaction(x: box.x, y: box.y, width: box.width, height: box.height, colour: colour)
            else { return nil }
            next.redactions[index] = redaction
        case .effect(let index):
            let old = effects[index], r = old.rectangle
            if change == .delete { next.effects.remove(at: index); return next }
            guard let box = Self.box(MarkBox(x: r.x, y: r.y, width: r.width, height: r.height), change) else { return nil }
            let kind: DocumentEffect.Kind = switch old.kind {
            case .blur: .blur(x: box.x, y: box.y, width: box.width, height: box.height)
            case .magnify: .magnify(x: box.x, y: box.y, width: box.width, height: box.height)
            }
            guard let effect = DocumentEffect(kind) else { return nil }
            next.effects[index] = effect
        case .annotation(let index):
            if change == .delete { next.annotations.remove(at: index); return next }
            guard let annotation = Self.annotation(annotations[index], change) else { return nil }
            next.annotations[index] = annotation
        }
        return next == self ? nil : next
    }

    /// A box moved or resized. Recolouring keeps it; a width change does not apply to boxes.
    private static func box(_ box: MarkBox, _ change: MarkChange) -> MarkBox? {
        switch change {
        case let .move(dx, dy):
            return MarkBox(x: box.x + dx, y: box.y + dy, width: box.width, height: box.height)
        case let .resize(handle, x, y):
            // The opposite corner stays where it is.
            let fixed: (x: Double, y: Double)
            switch handle {
            case .topLeft: fixed = (box.x + box.width, box.y + box.height)
            case .topRight: fixed = (box.x, box.y + box.height)
            case .bottomLeft: fixed = (box.x + box.width, box.y)
            case .bottomRight: fixed = (box.x, box.y)
            case .tail, .tip, .bend, .trailing: return nil
            }
            return MarkBox(x: min(fixed.x, x), y: min(fixed.y, y), width: abs(x - fixed.x), height: abs(y - fixed.y))
        case .recolour:
            return box
        case .rewidth, .restyle, .relabel, .retext, .delete:
            return nil
        }
    }

    private static func annotation(_ old: DocumentAnnotation, _ change: MarkChange) -> DocumentAnnotation? {
        var colour = old.colour, width = old.width, kind = old.kind, style = old.style, bend: ArrowBend? = old.bend
        var label = old.label
        switch (change, old.kind) {
        case let (.recolour(ink), _):
            colour = ink
        case let (.rewidth(value), .rectangle), let (.rewidth(value), .arrow):
            width = value
        case (.rewidth, .text), (.delete, _), (.restyle, .rectangle), (.restyle, .text), (.relabel, .rectangle),
             (.relabel, .arrow), (.retext, .rectangle), (.retext, .arrow):
            return nil
        case let (.relabel(format), .text):
            label = format
        case let (.retext(characters), .text(x, y, _)):
            kind = .text(x: x, y: y, characters: characters)
        case let (.resize(.trailing, handleX, _), .text(x, _, _)):
            // The handle sits on the box's right edge, past the style's margin.
            guard let format = old.label.with(wrapWidth: handleX - x - old.label.margin.horizontal) else { return nil }
            label = format
        case let (.restyle(next), .arrow):
            // A Curved arrow keeps its bend; one that becomes Curved bows as a new one does.
            style = next
            if old.style != .curved { bend = nil }
        case let (.move(dx, dy), .arrow(x0, y0, x1, y1)):
            kind = .arrow(x0: x0 + dx, y0: y0 + dy, x1: x1 + dx, y1: y1 + dy)
        case let (.move(dx, dy), .text(x, y, characters)):
            kind = .text(x: x + dx, y: y + dy, characters: characters)
        case let (.resize(.tail, x, y), .arrow(_, _, x1, y1)):
            kind = .arrow(x0: x, y0: y, x1: x1, y1: y1)
        case let (.resize(.tip, x, y), .arrow(x0, y0, _, _)):
            kind = .arrow(x0: x0, y0: y0, x1: x, y1: y)
        case let (.resize(.bend, x, y), .arrow(x0, y0, x1, y1)):
            guard old.style == .curved else { return nil }
            bend = ArrowBend.through(CGPoint(x: x, y: y), tail: CGPoint(x: x0, y: y0), tip: CGPoint(x: x1, y: y1))
            guard bend != nil else { return nil }
        case (.resize, .arrow), (.resize, .text):
            return nil
        case let (_, .rectangle(x, y, w, h)):
            guard let box = box(MarkBox(x: x, y: y, width: w, height: h), change) else { return nil }
            kind = .rectangle(x: box.x, y: box.y, width: box.width, height: box.height)
        }
        return DocumentAnnotation(kind, colour: colour, width: width, style: style, bend: bend, label: label)
    }

    /// What the mark is called in the Undo menu: "Solid Redaction", "Blur", "Shape", "Label"…
    public func noun(for mark: MarkReference) -> String {
        guard contains(mark) else { return "Mark" }
        switch mark {
        case .redaction: return "Solid Redaction"
        case .effect(let index):
            switch effects[index].kind {
            case .blur: return "Blur"
            case .magnify: return "Magnify"
            }
        case .annotation(let index):
            switch annotations[index].kind {
            case .rectangle: return "Shape"
            case .arrow: return annotations[index].style == .line ? "Line" : "Arrow"
            case .text: return "Label"
            }
        }
    }

    /// The mark's VoiceOver label, with positions relative to the crop's top-left.
    public func accessibilityLabel(for mark: MarkReference) -> String {
        guard let box = bounds(of: mark) else { return "" }
        let ox = crop?.x ?? 0, oy = crop?.y ?? 0
        func n(_ value: Double) -> String { String(Int(value.rounded())) }
        let size = "\(n(box.width)) by \(n(box.height)) points at \(n(box.x - ox)), \(n(box.y - oy))"
        switch mark {
        case .redaction: return "Solid redaction, \(size). Hides the pixels under it."
        case .effect(let index):
            switch effects[index].kind {
            case .blur: return "Blur, \(size). Does not hide pixels."
            case .magnify: return "Magnify, \(size). Does not hide pixels."
            }
        case .annotation(let index):
            switch annotations[index].kind {
            case .rectangle: return "Shape, rectangle outline, \(size)"
            case let .arrow(x0, y0, x1, y1):
                let ends = "from \(n(x0 - ox)), \(n(y0 - oy)) to \(n(x1 - ox)), \(n(y1 - oy))"
                switch annotations[index].style {
                case .standard: return "Arrow \(ends)"
                case .curved: return "Curved arrow \(ends)"
                case .double: return "Double arrow \(ends)"
                case .line: return "Line \(ends)"
                }
            case let .text(_, _, characters): return "Label, \(characters), at \(n(box.x - ox)), \(n(box.y - oy))"
            }
        }
    }
}

/// The editor's selected mark and every change to marks, each one undo step on the edits' undo
/// manager (ticket 84). Points are canvas points: document points from the crop's top-left, as the
/// canvas reports them. The window only forwards pointer and key events and draws what this reports.
@MainActor public final class MarkEditor {
    public let document: UndoableEdits
    private var chosen: MarkReference?
    /// Called when the selection changes (not when an edit moves the selected mark).
    public var onSelectionChange: (() -> Void)?

    /// A press that took hold of a mark: its body to move it, or one of its handles to resize it.
    public struct Grab: Equatable, Sendable {
        public let mark: MarkReference
        public let handle: MarkHandle?
        public init(mark: MarkReference, handle: MarkHandle?) {
            self.mark = mark
            self.handle = handle
        }
    }

    public init(_ document: UndoableEdits) {
        self.document = document
    }

    private var edits: DocumentEdits { document.edits }
    private var origin: (x: Double, y: Double) { (edits.crop?.x ?? 0, edits.crop?.y ?? 0) }

    /// The selected mark, if it still exists (an undo can remove it).
    public var selection: MarkReference? {
        guard let chosen, edits.contains(chosen) else { return nil }
        return chosen
    }

    public func select(_ mark: MarkReference?) {
        let next = mark.flatMap { edits.contains($0) ? $0 : nil }
        let changed = next != selection
        chosen = next
        if changed { onSelectionChange?() }
    }

    /// Deselects; returns false when nothing was selected (so Esc can do its usual job).
    @discardableResult public func deselect() -> Bool {
        let had = selection != nil
        select(nil)
        return had
    }

    /// A click (a press with no drag): selects the topmost mark there, or deselects.
    /// Returns true when it selected a mark.
    @discardableResult public func click(atX x: Double, y: Double, tolerance: Double) -> Bool {
        let mark = edits.mark(atX: x + origin.x, y: y + origin.y, tolerance: tolerance)
        select(mark)
        return mark != nil
    }

    /// A press: the selected mark's handle, then its body. With `anyMark` (the Select tool) a press
    /// on another mark selects it and takes hold of it. Nil means the press is the tool's to draw.
    public func press(atX x: Double, y: Double, tolerance: Double, anyMark: Bool) -> Grab? {
        let px = x + origin.x, py = y + origin.y
        if let selected = selection {
            if let handle = edits.handle(of: selected, atX: px, y: py, tolerance: tolerance * 1.5) {
                return Grab(mark: selected, handle: handle)
            }
            if edits.hits(selected, px, py, tolerance) { return Grab(mark: selected, handle: nil) }
        }
        guard anyMark, let mark = edits.mark(atX: px, y: py, tolerance: tolerance) else { return nil }
        select(mark)
        return Grab(mark: mark, handle: nil)
    }

    /// Ends a drag that began with `grab`: a handle resizes to the release point; the body moves by
    /// the drag. A drag shorter than `slop` is a click and changes nothing. Returns true when the
    /// mark changed.
    @discardableResult public func release(_ grab: Grab, fromX: Double, fromY: Double, toX: Double, toY: Double,
                                           slop: Double = 0) -> Bool {
        guard hypot(toX - fromX, toY - fromY) > slop else { return false }
        if let handle = grab.handle {
            return change(grab.mark, .resize(handle, x: toX + origin.x, y: toY + origin.y), verb: "Resize")
        }
        return change(grab.mark, .move(dx: toX - fromX, dy: toY - fromY), verb: "Move")
    }

    /// Tab and Shift-Tab: the next or previous mark in paint order. Returns false after the last
    /// (or before the first) mark, with nothing selected, so focus can leave the canvas.
    public func selectNext(backward: Bool = false) -> Bool {
        let all = edits.marks
        guard !all.isEmpty else { deselect(); return false }
        guard let current = selection, let index = all.firstIndex(of: current) else {
            select(backward ? all.last : all.first)
            return true
        }
        let next = backward ? index - 1 : index + 1
        guard all.indices.contains(next) else { deselect(); return false }
        select(all[next])
        return true
    }

    /// Arrow keys: moves the selected mark by `(dx, dy)` points.
    @discardableResult public func nudge(dx: Double, dy: Double) -> Bool {
        guard let mark = selection else { return false }
        return change(mark, .move(dx: dx, dy: dy), verb: "Move")
    }

    /// Delete: removes the selected mark and clears the selection.
    @discardableResult public func deleteSelection() -> Bool {
        guard let mark = selection else { return false }
        let changed = change(mark, .delete, verb: "Delete")
        if changed { select(nil) }
        return changed
    }

    /// A new ink for the selected annotation, or fill for the selected Solid redaction (alpha 255 only).
    @discardableResult public func recolourSelection(_ colour: RGBAPixel) -> Bool {
        guard let mark = selection else { return false }
        return change(mark, .recolour(colour), verb: "Restyle")
    }

    /// A new line width for the selected shape or arrow.
    @discardableResult public func rewidthSelection(_ width: Double) -> Bool {
        guard let mark = selection else { return false }
        return change(mark, .rewidth(width), verb: "Restyle")
    }

    /// The selected Solid redaction's fill colour; nil when no redaction is selected.
    public var selectionFill: RGBAPixel? {
        guard case .redaction(let index)? = selection else { return nil }
        return edits.redactions[index].colour
    }

    /// A new style for the selected arrow or line (ticket 85).
    @discardableResult public func restyleSelection(_ style: ArrowStyle) -> Bool {
        guard let mark = selection else { return false }
        return change(mark, .restyle(style), verb: "Restyle")
    }

    /// A new style, size or wrap width for the selected label (ticket 86).
    @discardableResult public func relabelSelection(_ format: LabelFormat) -> Bool {
        guard let mark = selection else { return false }
        return change(mark, .relabel(format), verb: "Restyle")
    }

    /// The selected label's style, size and wrap width; nil when no label is selected.
    public var selectionLabel: LabelFormat? {
        guard case .annotation(let index)? = selection, case .text = edits.annotations[index].kind else { return nil }
        return edits.annotations[index].label
    }

    /// The label under `(x, y)` in canvas points, if the topmost mark there is one: the Text tool
    /// edits it rather than starting a new label.
    public func label(atX x: Double, y: Double, tolerance: Double) -> MarkReference? {
        guard let mark = edits.mark(atX: x + origin.x, y: y + origin.y, tolerance: tolerance),
              case .annotation(let index) = mark, case .text = edits.annotations[index].kind else { return nil }
        return mark
    }

    /// The selected mark's style, when it is an arrow or a line.
    public var selectionStyle: ArrowStyle? {
        guard case .annotation(let index)? = selection, case .arrow = edits.annotations[index].kind else { return nil }
        return edits.annotations[index].style
    }

    /// The selected mark's line width, when it has one to change.
    public var selectionWidth: Double? {
        guard case .annotation(let index)? = selection else { return nil }
        let annotation = edits.annotations[index]
        if case .text = annotation.kind { return nil }
        return annotation.width
    }

    /// The selected mark's outline and handles, in canvas points, for drawing.
    public var selectionOutline: (box: MarkBox, handles: [(handle: MarkHandle, x: Double, y: Double)])? {
        guard let mark = selection, let box = edits.bounds(of: mark) else { return nil }
        let o = origin
        return (MarkBox(x: box.x - o.x, y: box.y - o.y, width: box.width, height: box.height),
                edits.handles(of: mark).map { ($0.handle, $0.x - o.x, $0.y - o.y) })
    }

    /// Every mark with its VoiceOver label and box in canvas points, in Tab order.
    public var accessibleMarks: [(mark: MarkReference, label: String, box: MarkBox)] {
        let o = origin
        return edits.marks.compactMap { mark in
            edits.bounds(of: mark).map { box in
                (mark, edits.accessibilityLabel(for: mark), MarkBox(x: box.x - o.x, y: box.y - o.y, width: box.width, height: box.height))
            }
        }
    }

    private func change(_ mark: MarkReference, _ change: MarkChange, verb: String) -> Bool {
        guard let next = edits.applying(change, to: mark) else { return false }
        document.apply(next, named: "\(verb) \(edits.noun(for: mark))")
        return true
    }
}

/// The canvas keys for marks (ticket 84): Tab and Shift-Tab step through marks, the arrow keys move
/// the selected mark by 1 point (10 with Shift), and Delete or Forward Delete removes it.
public enum MarkKey: Equatable, Sendable {
    case next, previous, delete
    case nudge(dx: Double, dy: Double)

    public static func action(characters: String?, shift: Bool) -> MarkKey? {
        guard let key = characters?.unicodeScalars.first?.value else { return nil }
        let step = shift ? 10.0 : 1.0
        switch key {
        case 0x09: return shift ? .previous : .next
        case 0x19: return .previous
        case 0x7f, 0x08, 0xF728: return .delete
        case 0xF700: return .nudge(dx: 0, dy: -step)
        case 0xF701: return .nudge(dx: 0, dy: step)
        case 0xF702: return .nudge(dx: -step, dy: 0)
        case 0xF703: return .nudge(dx: step, dy: 0)
        default: return nil
        }
    }
}
