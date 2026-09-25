import CoreGraphics
import CoreText
import Foundation
import FrisketCore
import Testing

/// Ticket 86: labels typed on the image, in the pinned font, with a size, a style (Standard,
/// Outlined, Box) and a width handle that wraps the text.
///
/// Pixel goldens compare only pixels well inside a glyph stem or a box, or well outside them;
/// antialiased edge pixels are not compared. The preview and the delivered image are compared byte for byte.
@MainActor @Suite struct LabelTests {
    private static let price = "v2.1 $4.99 -10%"
    private static let base = RGBAPixel(red: 0x20, green: 0x40, blue: 0x60, alpha: 0xff)
    private static let ink = DocumentAnnotation.stroke
    private static let white = RGBAPixel(red: 255, green: 255, blue: 255, alpha: 255)

    /// Ends the current event, so the undo manager closes its group (see `UndoableEditsTests`).
    private static func endEvent() {
        RunLoop.main.add(Timer(timeInterval: 0.001, repeats: false) { _ in }, forMode: .default)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    }

    private static func document(_ annotations: [DocumentAnnotation] = []) throws -> UndoableEdits {
        UndoableEdits(try #require(DocumentEdits(scale: 1, annotations: annotations)), undoManager: UndoManager())
    }

    private static func rendered(_ annotations: [DocumentAnnotation], width: Int = 260, height: Int = 120,
                                 scale: Double = 1) throws -> Picture {
        let bytes = (0..<(width * height)).flatMap { _ in [base.red, base.green, base.blue, base.alpha] }
        let png = try CaptureRendererTests.encode(bytes, width: width, height: height)
        return try delivered(png, try #require(DocumentEdits(scale: scale, annotations: annotations)))
    }

    // MARK: Typing

    @Test func typingAPriceKeepsEveryCharacterInThePinnedFont() throws {
        let document = try Self.document()
        let session = LabelSession(document: document, x: 10, y: 20)
        for count in 1...Self.price.count {
            session.type(String(Self.price.prefix(count)))
            Self.endEvent()
        }
        let label = try #require(document.edits.annotations.first)
        #expect(document.edits.annotations.count == 1)
        #expect(label.kind == .text(x: 10, y: 20, characters: Self.price), "exactly the typed characters")

        // One line holding every character, each with its own glyph in the pinned font: nothing is
        // dropped, case-folded or drawn from a fallback font.
        let layout = LabelLayout(characters: Self.price, format: label.label)
        #expect(layout.lines == [0..<15])
        let font = CTFontCreateWithName(LabelLayout.fontName as CFString, 18, nil)
        #expect(CTFontCopyPostScriptName(font) as String == "HelveticaNeue-Bold")
        let units = Array(Self.price.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        #expect(CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count))
        #expect(!glyphs.contains(0))
        #expect(Set(glyphs.enumerated().filter { units[$0.offset] == units[0] }.map(\.element)).count == 1)
        #expect(glyphs[0] != CTFontGetGlyphWithName(font, "V" as CFString), "lowercase v stays lowercase")

        // The ink spans the text's measured width, no more.
        let picture = try Self.rendered([label])
        let inkColumns = (0..<picture.width).filter { x in (0..<picture.height).contains { picture.pixel(x: x, y: $0) == Self.ink } }
        let first = try #require(inkColumns.first), last = try #require(inkColumns.last)
        #expect(first >= 10 && first <= 12)
        #expect(Double(last) <= 10 + layout.textWidth + 1 && Double(last) >= 10 + layout.textWidth - 4,
                "ink ends at \(last); the text is \(layout.textWidth) wide")
    }

    @Test func aTypingSessionIsOneUndoStepOnTheSharedUndoManager() throws {
        let document = try Self.document()
        let session = LabelSession(document: document, x: 4, y: 4)
        var seen: [Bool] = []
        document.onChange = { seen.append(session.isCurrent) }
        for text in ["H", "Hi", "Hi!"] {
            session.type(text)
            Self.endEvent()
        }
        #expect(seen == [true, true, true], "the window's change handler sees its own typing as current")
        #expect(document.undoManager.undoActionName == "Label")
        document.undoManager.undo()
        #expect(document.edits.annotations.isEmpty, "one undo removes the whole label")
        #expect(!session.isCurrent, "the window ends a session an undo replaced")
        #expect(!document.undoManager.canUndo)
        document.undoManager.redo()
        #expect(document.edits.annotations.first?.kind == .text(x: 4, y: 4, characters: "Hi!"))

        // Editing an existing label is one "Edit Label" step back to the old text.
        Self.endEvent()
        let edit = try #require(LabelSession(document: document, editing: .annotation(0)))
        #expect(edit.characters == "Hi!")
        edit.type("Hi")
        Self.endEvent()
        edit.type("Hey")
        Self.endEvent()
        #expect(document.undoManager.undoActionName == "Edit Label")
        document.undoManager.undo()
        #expect(document.edits.annotations.first?.kind == .text(x: 4, y: 4, characters: "Hi!"))
    }

    @Test func anEmptyLabelLeavesNothingBehind() throws {
        let document = try Self.document()
        let session = LabelSession(document: document, x: 4, y: 4)
        session.type("  ")
        #expect(session.isEmpty && document.edits.annotations.isEmpty, "blank text is not a label")
        session.type("  a")
        #expect(document.edits.annotations.count == 1 && !session.isEmpty)
        session.type("")
        #expect(session.isEmpty && document.edits.annotations.isEmpty && document.isUnchanged,
                "deleting every character takes the label out, so Esc cancels it and Close does not ask")
        #expect(session.box.height > 0, "the caret box keeps one line's height")
    }

    // MARK: Size, style and width

    @Test func theWidthHandleWrapsTheText() throws {
        let text = "alpha beta gamma delta"
        let editor = MarkEditor(try Self.document([try #require(DocumentAnnotation(.text(x: 10, y: 10, characters: text)))]))
        editor.select(.annotation(0))
        let one = try #require(editor.selectionOutline)
        #expect(one.handles.map(\.handle) == [.trailing])
        let handle = one.handles[0]
        #expect(handle.x == one.box.x + one.box.width && handle.y == one.box.y + one.box.height / 2)

        let grab = try #require(editor.press(atX: handle.x, y: handle.y, tolerance: 3, anyMark: false))
        #expect(grab.handle == .trailing)
        #expect(editor.release(grab, fromX: handle.x, fromY: handle.y, toX: 10 + 70, toY: handle.y))
        #expect(editor.document.undoManager.undoActionName == "Resize Label")
        let format = try #require(editor.selectionLabel)
        #expect(format.wrapWidth == 70)
        let layout = LabelLayout(characters: text, format: format)
        #expect(layout.lines.count >= 3, "\(layout.lines)")
        #expect(layout.lines.map { String(Array(text.utf16)[$0].map { Character(UnicodeScalar($0)!) }) }.joined() == text)
        let wrapped = try #require(editor.selectionOutline?.box)
        #expect(wrapped.width == 70 && wrapped.height > one.box.height * 2)

        let picture = try Self.rendered(editor.document.edits.annotations)
        let inkColumns = (0..<picture.width).filter { x in (0..<picture.height).contains { picture.pixel(x: x, y: $0) == Self.ink } }
        #expect((inkColumns.last ?? 999) <= 10 + 70 + 1, "no ink past the wrap width")
        let inkRows = (0..<picture.height).filter { y in (0..<picture.width).contains { picture.pixel(x: $0, y: y) == Self.ink } }
        #expect((inkRows.last ?? 0) > 10 + Int(one.box.height * 2), "the text continues on later lines")

        // Never narrower than one em.
        let side = try #require(editor.selectionOutline?.handles.first)
        let narrow = try #require(editor.press(atX: side.x, y: side.y, tolerance: 3, anyMark: false))
        #expect(narrow.handle == .trailing)
        editor.release(narrow, fromX: side.x, fromY: side.y, toX: 0, toY: side.y)
        #expect(editor.selectionLabel?.wrapWidth == LabelFormat.defaultSize)
    }

    @Test func sizeAndStyleRestyleTheSelectedLabelAsOneStepEach() throws {
        let editor = MarkEditor(try Self.document([try #require(DocumentAnnotation(.text(x: 10, y: 10, characters: "Hi")))]))
        editor.select(.annotation(0))
        let small = try #require(editor.selectionOutline?.box)
        #expect(editor.selectionLabel == .standard)
        #expect(editor.relabelSelection(try #require(LabelFormat.standard.with(size: 36))))
        #expect(editor.document.undoManager.undoActionName == "Restyle Label")
        let large = try #require(editor.selectionOutline?.box)
        #expect(abs(large.height - 2 * small.height) < 0.01 && abs(large.width - 2 * small.width) < 0.5)
        #expect(editor.relabelSelection(try #require(editor.selectionLabel).with(style: .box)))
        let boxed = try #require(editor.selectionOutline?.box)
        #expect(boxed.x < 10 && boxed.y < 10 && boxed.width > large.width, "a box pads the text")
        #expect(!editor.relabelSelection(try #require(editor.selectionLabel)), "the same format changes nothing")

        // Only labels take a label format; labels take no line width.
        let arrow = try #require(DocumentAnnotation(.arrow(x0: 0, y0: 0, x1: 9, y1: 9)))
        #expect(DocumentAnnotation(.arrow(x0: 0, y0: 0, x1: 9, y1: 9), label: LabelFormat(style: .box)!)?.label == .standard)
        var edits = editor.document.edits
        edits.annotations.append(arrow)
        #expect(edits.applying(.relabel(.standard), to: .annotation(1)) == nil)
        #expect(edits.applying(.rewidth(4), to: .annotation(0)) == nil)
        #expect(LabelFormat(size: 2) == nil && LabelFormat(size: .nan) == nil)
        #expect(LabelFormat.sizes.contains(LabelFormat.defaultSize))
    }

    /// The stem of a large "I", in output pixels: a column and row well inside the glyph.
    private static func stem(x: Double, y: Double, size: Double) -> (x: Int, y: Int, right: Int) {
        let font = CTFontCreateWithName(LabelLayout.fontName as CFString, size, nil)
        var glyph = CTFontGetGlyphWithName(font, "I" as CFString)
        var rect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &rect, 1)
        let top = y + Double(CTFontGetAscent(font))
        return (Int(x + rect.midX), Int(top - rect.midY), Int((x + rect.maxX).rounded()))
    }

    @Test func eachStyleDrawsItsOwnPixels() throws {
        let size = 48.0, x = 20.0, y = 20.0
        let stem = Self.stem(x: x, y: y, size: size)
        func picture(_ style: LabelStyle) throws -> Picture {
            let format = try #require(LabelFormat(style: style, size: size))
            return try Self.rendered([try #require(DocumentAnnotation(.text(x: x, y: y, characters: "I"), label: format))])
        }
        let standard = try picture(.standard)
        #expect(standard.pixel(x: stem.x, y: stem.y) == Self.ink, "Standard: ink glyphs")
        #expect(standard.pixel(x: stem.right + 3, y: stem.y) == Self.base, "Standard: 1 px plate only")

        let outlined = try picture(.outlined)
        #expect(outlined.pixel(x: stem.x, y: stem.y) == Self.white, "Outlined: white glyphs")
        #expect(outlined.pixel(x: stem.right + 2, y: stem.y) == Self.ink, "Outlined: an ink outline 5 px wide")
        #expect(outlined.pixel(x: stem.right + 8, y: stem.y) == Self.base)

        let boxed = try picture(.box)
        let format = try #require(LabelFormat(style: .box, size: size))
        let box = LabelLayout(characters: "I", format: format).bounds
        let minX = Int((x + box.x).rounded(.down)), minY = Int((y + box.y).rounded(.down))
        let maxX = Int((x + box.x + box.width).rounded(.up)), maxY = Int((y + box.y + box.height).rounded(.up))
        #expect(boxed.pixel(x: stem.x, y: stem.y) == Self.white, "Box: white glyphs")
        for (px, py) in [(minX, minY), (maxX - 1, minY), (minX, maxY - 1), (maxX - 1, maxY - 1)] {
            #expect(boxed.pixel(x: px, y: py) == Self.ink, "Box: filled to its snapped corner \(px), \(py)")
        }
        #expect(boxed.pixel(x: minX - 1, y: minY) == Self.white, "Box: a 1 px plate")
        #expect(boxed.pixel(x: minX - 2, y: minY) == Self.base && boxed.pixel(x: maxX + 1, y: maxY) == Self.base)

        // A light ink gets black text.
        let yellow = RGBAPixel(red: 0xff, green: 0xd6, blue: 0x0a, alpha: 0xff)
        let light = try Self.rendered([try #require(DocumentAnnotation(.text(x: x, y: y, characters: "I"), colour: yellow,
                                                                       label: format))])
        #expect(light.pixel(x: stem.x, y: stem.y) == RGBAPixel(red: 0, green: 0, blue: 0, alpha: 255))
    }

    /// Delivered image = editor preview for every style and size, wrapped or not, at 1× and 2×, with a crop.
    @Test(arguments: [1.0, 2.0])
    func everyLabelRendersTheSameInThePreviewAndTheSavedOutput(scale: Double) throws {
        let width = 480, height = 360
        let png = try CaptureRendererTests.encode(CaptureRendererTests.pattern(width: width, height: height),
                                                  width: width, height: height)
        let preview = try CaptureRenderer().preview(png)
        let redaction = try #require(SolidRedaction(x: 30, y: 30, width: 20, height: 12))
        let crop = try #require(DocumentCrop(x: 2.5, y: 1.25, width: 200, height: 160))
        for style in LabelStyle.allCases {
            for size in LabelFormat.sizes {
                for wrap in [nil, 60.0] {
                    let format = try #require(LabelFormat(style: style, size: size, wrapWidth: wrap))
                    let label = try #require(DocumentAnnotation(.text(x: 12.3, y: 20.6, characters: Self.price), label: format))
                    let edits = try #require(DocumentEdits(scale: scale, crop: crop, redactions: [redaction],
                                                           annotations: [label]))
                    let saved = try delivered(png, edits)
                    let shown = try previewed(preview, edits)
                    #expect(saved.bytes == shown.bytes, "\(style) \(size) pt wrap \(String(describing: wrap)) at \(scale)×")
                }
            }
        }
    }
}
