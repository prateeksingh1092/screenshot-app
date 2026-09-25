import CoreGraphics
import CoreText
import Foundation

/// How a label is drawn (ticket 86, story 104).
public enum LabelStyle: String, CaseIterable, Sendable {
    /// Ink glyphs with a 1 px white plate around them (decision 68).
    case standard
    /// White glyphs (black in a light ink) inside an ink outline.
    case outlined
    /// White glyphs (black on a light ink) on a box filled with the ink.
    case box

    public var title: String {
        switch self {
        case .standard: "Standard"
        case .outlined: "Outlined"
        case .box: "Box"
        }
    }
}

/// A label's style, size and wrap width. The width is set with the label's side handle; with none,
/// the label is as wide as its text and only breaks at line breaks.
public struct LabelFormat: Equatable, Sendable {
    /// The sizes the editor offers, in document points; 18 is the default (decision 68's size).
    public static let sizes: [Double] = [14, 18, 24, 36, 48]
    public static let defaultSize = 18.0
    /// Standard, 18 pt, no wrap width.
    public static let standard = LabelFormat(checked: .standard, size: defaultSize, wrapWidth: nil)

    public let style: LabelStyle
    /// The font size in document points.
    public let size: Double
    /// Where lines wrap, in document points from the text's left edge; never narrower than one em.
    public let wrapWidth: Double?

    /// Refuses a size outside [6, 144] points or a wrap width that is not finite.
    public init?(style: LabelStyle = .standard, size: Double = LabelFormat.defaultSize, wrapWidth: Double? = nil) {
        guard size.isFinite, size >= 6, size <= 144 else { return nil }
        if let wrapWidth, !wrapWidth.isFinite { return nil }
        self.init(checked: style, size: size, wrapWidth: wrapWidth)
    }

    private init(checked style: LabelStyle, size: Double, wrapWidth: Double?) {
        self.style = style
        self.size = size
        self.wrapWidth = wrapWidth.map { max($0, size) }
    }

    public func with(style: LabelStyle) -> LabelFormat { LabelFormat(checked: style, size: size, wrapWidth: wrapWidth) }
    public func with(size: Double) -> LabelFormat? { LabelFormat(style: style, size: size, wrapWidth: wrapWidth) }
    public func with(wrapWidth: Double?) -> LabelFormat? { LabelFormat(style: style, size: size, wrapWidth: wrapWidth) }

    /// How far the style reaches past the text on each side, in document points: an outline's
    /// thickness, or a box's padding.
    public var margin: (horizontal: Double, vertical: Double) {
        switch style {
        case .standard: (0, 0)
        case .outlined: (outline, outline)
        case .box: (size * 0.3, size * 0.15)
        }
    }

    /// An Outlined label's ink outside the glyphs, in document points.
    var outline: Double { size / 9 }
}

/// Where a label's lines break and how big it is, in document points (ticket 86). Lines are broken
/// once, with the pinned font at the label's own size, so the preview and every output wrap alike
/// at any scale; `AnnotationPainter` draws the same line ranges with the font scaled.
public struct LabelLayout: Equatable, Sendable {
    /// The pinned label font (decision 68). Every Mac ships it.
    public static let fontName = "HelveticaNeue-Bold"

    /// Each line's range of UTF-16 units in the characters.
    public let lines: [Range<Int>]
    /// The text's width: the wrap width when there is one, else the widest line.
    public let textWidth: Double
    /// From the first line's top to the last line's bottom.
    public let textHeight: Double
    /// The distance between baselines.
    public let lineHeight: Double
    public let format: LabelFormat

    public init(characters: String, format: LabelFormat) {
        self.format = format
        let font = Self.font(size: format.size)
        let metrics = Self.metrics(font)
        lineHeight = metrics.lineHeight
        var lines: [Range<Int>] = [], widest = 0.0
        if let typesetter = Self.typesetter(characters, font: font) {
            let length = (characters as NSString).length
            let limit = format.wrapWidth ?? 1e7
            var start = 0
            while start < length {
                let count = CTTypesetterSuggestLineBreak(typesetter, start, limit)
                guard count > 0 else { break }
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                widest = max(widest, CTLineGetTypographicBounds(line, nil, nil, nil))
                lines.append(start..<(start + count))
                start += count
            }
        }
        self.lines = lines
        textWidth = format.wrapWidth ?? widest
        textHeight = metrics.ascent + metrics.descent + Double(max(lines.count, 1) - 1) * metrics.lineHeight
    }

    /// The label's box relative to where its text starts: the text, plus the style's margin.
    public var bounds: MarkBox {
        let margin = format.margin
        return MarkBox(x: -margin.horizontal, y: -margin.vertical, width: textWidth + 2 * margin.horizontal,
                       height: textHeight + 2 * margin.vertical)
    }

    static func font(size: Double) -> CTFont { CTFontCreateWithName(fontName as CFString, CGFloat(size), nil) }

    static func metrics(_ font: CTFont) -> (ascent: Double, descent: Double, lineHeight: Double) {
        let ascent = Double(CTFontGetAscent(font)), descent = Double(CTFontGetDescent(font))
        return (ascent, descent, ascent + descent + Double(CTFontGetLeading(font)))
    }

    static func typesetter(_ characters: String, font: CTFont, colourFromContext: Bool = false) -> CTTypesetter? {
        var attributes: [CFString: Any] = [kCTFontAttributeName: font]
        if colourFromContext { attributes[kCTForegroundColorFromContextAttributeName] = true }
        guard let string = CFAttributedStringCreate(nil, characters as CFString, attributes as CFDictionary) else { return nil }
        return CTTypesetterCreateWithAttributedString(string)
    }
}

extension AnnotationPainter {
    /// Draws one layer of a label whose text starts at `top` (output pixels). Standard: the plate
    /// strokes the glyphs 2 px wide in white, the ink fills them. Outlined: the plate strokes them
    /// wider than the outline, the ink strokes the outline, then the glyphs fill white (black in a
    /// light ink). Box: the
    /// plate fills the box snapped outward and 1 px larger, the ink fills the box, then the glyphs
    /// fill in white (black on a light ink).
    static func drawLabel(_ characters: String, format: LabelFormat, colour: RGBAPixel, top: CGPoint, scale: Double,
                          layer: Layer, in context: CGContext) {
        let layout = LabelLayout(characters: characters, format: format)
        let font = LabelLayout.font(size: format.size * scale)
        guard let typesetter = LabelLayout.typesetter(characters, font: font, colourFromContext: true) else { return }
        let metrics = LabelLayout.metrics(font)
        context.saveGState()
        defer { context.restoreGState() }
        func glyphs(_ mode: CGTextDrawingMode) {
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            context.setTextDrawingMode(mode)
            for (index, range) in layout.lines.enumerated() {
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: range.lowerBound, length: range.count))
                context.textPosition = CGPoint(x: top.x, y: top.y + metrics.ascent + Double(index) * metrics.lineHeight)
                CTLineDraw(line, context)
            }
        }
        switch format.style {
        case .standard:
            context.setLineWidth(2)
            glyphs(layer == .ink ? .fill : .stroke)
        case .outlined:
            let outline = max(1, (format.outline * scale).rounded())
            if layer == .plate {
                context.setLineWidth(2 * outline + 2)
                glyphs(.stroke)
            } else {
                context.setLineWidth(2 * outline)
                glyphs(.stroke)
                context.setFillColor(letterColour(on: colour))
                glyphs(.fill)
            }
        case .box:
            // Snapped outward to whole output pixels, like a shape, so its edges are exact.
            let box = layout.bounds
            let minX = (top.x + box.x * scale).rounded(.down), minY = (top.y + box.y * scale).rounded(.down)
            let maxX = (top.x + (box.x + box.width) * scale).rounded(.up)
            let maxY = (top.y + (box.y + box.height) * scale).rounded(.up)
            let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            if layer == .plate {
                context.fill(rect.insetBy(dx: -1, dy: -1))
            } else {
                context.fill(rect)
                context.setFillColor(letterColour(on: colour))
                glyphs(.fill)
            }
        }
    }

    /// The letters inside an Outlined or Box label: white on a dark or mid ink, black on a light
    /// one (Yellow, White), so the letters never vanish into their ink (ticket 99).
    static func letterColour(on ink: RGBAPixel) -> CGColor {
        let luma = (0.299 * Double(ink.red) + 0.587 * Double(ink.green) + 0.114 * Double(ink.blue)) / 255
        return luma > 0.6 ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) : plateColour
    }
}

/// Typing one label on the canvas (ticket 86). The window shows a caret and a box; every change to
/// the typed text goes into the edits at once, so the canvas shows the label exactly as it will be
/// delivered. The whole session is one undo step on the edits' undo manager (the window's, decision
/// 77), named "Label" for a new label or "Edit Label" for an existing one. While the text is blank
/// the label is not in the edits, so ending an empty session leaves nothing behind.
@MainActor public final class LabelSession {
    public let document: UndoableEdits
    /// Where the text starts, in document points of the uncropped capture.
    public let x: Double, y: Double
    public private(set) var colour: RGBAPixel
    public private(set) var characters: String
    public private(set) var format: LabelFormat
    /// The label's index in the annotations while it has visible characters.
    public private(set) var index: Int?
    private var written: DocumentEdits
    private let name: String
    private let key = UUID()

    /// A new label whose text starts at `(x, y)`, in document points of the uncropped capture.
    public init(document: UndoableEdits, x: Double, y: Double, format: LabelFormat = .standard,
                colour: RGBAPixel = DocumentAnnotation.stroke) {
        self.document = document
        self.x = x
        self.y = y
        self.format = format
        self.colour = colour
        characters = ""
        written = document.edits
        name = "Label"
    }

    /// Edits the existing label at `.annotation(index)`; nil when that mark is not a label.
    public init?(document: UndoableEdits, editing mark: MarkReference) {
        guard case .annotation(let index) = mark, document.edits.annotations.indices.contains(index),
              case let .text(x, y, characters) = document.edits.annotations[index].kind else { return nil }
        let label = document.edits.annotations[index]
        self.document = document
        self.x = x
        self.y = y
        self.characters = characters
        format = label.label
        colour = label.colour
        self.index = index
        written = document.edits
        name = "Edit Label"
    }

    /// False once another change (an undo, say) replaced what this session wrote; the window then
    /// ends the session.
    public var isCurrent: Bool { document.edits == written }

    /// True while the text has no visible character: Esc then cancels the label.
    public var isEmpty: Bool { characters.allSatisfy(\.isWhitespace) }

    /// The label as a mark, while it is in the edits.
    public var mark: MarkReference? { index.map(MarkReference.annotation) }

    /// The caret box, in document points of the uncropped capture: the label's box, or one empty
    /// line where the text starts.
    public var box: MarkBox {
        let layout = LabelLayout(characters: characters, format: format).bounds
        return MarkBox(x: x + layout.x, y: y + layout.y, width: max(layout.width, 1), height: layout.height)
    }

    /// The whole text typed so far replaces the label's characters.
    public func type(_ text: String) {
        guard isCurrent, text != characters else { return }
        characters = text
        var next = document.edits
        if let label = DocumentAnnotation(.text(x: x, y: y, characters: text), colour: colour, label: format) {
            if let index {
                next.annotations[index] = label
            } else {
                next.annotations.append(label)
                index = next.annotations.count - 1
            }
        } else if let index {
            next.annotations.remove(at: index)
            self.index = nil
        }
        // Written first: the document's change handler may ask `isCurrent`.
        written = next
        document.apply(next, named: name, coalescing: key)
    }

    /// A new ink for the label being typed (ticket 99): its own undo step once the label exists
    /// ("Restyle Label"). A colour that is not opaque is ignored.
    public func recolour(_ colour: RGBAPixel) {
        guard isCurrent, colour != self.colour, colour.alpha == 255 else { return }
        self.colour = colour
        guard let index, let label = DocumentAnnotation(.text(x: x, y: y, characters: characters), colour: colour,
                                                        label: format) else { return }
        var next = document.edits
        next.annotations[index] = label
        written = next
        document.apply(next, named: "Restyle Label")
    }

    /// A new style, size or wrap width for the label being typed: its own undo step once the label
    /// exists ("Restyle Label").
    public func restyle(_ format: LabelFormat) {
        guard isCurrent, format != self.format else { return }
        self.format = format
        guard let index, let label = DocumentAnnotation(.text(x: x, y: y, characters: characters), colour: colour,
                                                        label: format) else { return }
        var next = document.edits
        next.annotations[index] = label
        written = next
        document.apply(next, named: "Restyle Label")
    }
}
