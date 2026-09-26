import Foundation
import FrisketCore
import Testing

/// Ticket 99 (decision 92): six ink colours for arrows, lines, shapes and labels, offered in the
/// style bar for new marks and to recolour a selected one. Ink stays opaque, recolouring is one
/// named undo step, and the delivered image equals the preview in every colour.
@MainActor @Suite struct InkPaletteTests {
    private static func endEvent(_ undoManager: UndoManager) {
        RunLoop.main.add(Timer(timeInterval: 0.001, repeats: false) { _ in }, forMode: .default)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        #expect(undoManager.groupingLevel == 0)
    }

    /// A thick shape, a Standard arrow, a Line and a label, over a Solid redaction.
    private static func marked() throws -> DocumentEdits {
        let redaction = try #require(SolidRedaction(x: 60, y: 4, width: 12, height: 10))
        let shape = try #require(DocumentAnnotation(.rectangle(x: 4, y: 4, width: 40, height: 30), width: 8))
        let arrow = try #require(DocumentAnnotation(.arrow(x0: 4, y0: 44, x1: 60, y1: 44), width: 4))
        let line = try #require(DocumentAnnotation(.arrow(x0: 4, y0: 56, x1: 60, y1: 56), width: 4, style: .line))
        let label = try #require(DocumentAnnotation(.text(x: 4, y: 62, characters: "Ink")))
        return try #require(DocumentEdits(scale: 2, redactions: [redaction], annotations: [shape, arrow, line, label]))
    }

    @Test func thePaletteIsSixOpaqueNamedColoursWithRedFirst() {
        let palette = DocumentAnnotation.palette
        #expect(palette.map(\.name) == ["Red", "Yellow", "Blue", "Green", "Black", "White"])
        #expect(palette.first?.pixel == DocumentAnnotation.stroke, "Red is the default ink, so existing goldens hold")
        #expect(palette.allSatisfy { $0.pixel.alpha == 255 }, "ink is opaque")
        #expect(Set(palette.map(\.pixel)).count == palette.count)
        #expect(palette.first { $0.name == "Black" }?.pixel == RGBAPixel(red: 0, green: 0, blue: 0, alpha: 255))
        #expect(palette.first { $0.name == "White" }?.pixel == RGBAPixel(red: 255, green: 255, blue: 255, alpha: 255))
        #expect(DocumentAnnotation.inkName(DocumentAnnotation.stroke) == "Red")
        #expect(DocumentAnnotation.inkName(RGBAPixel(red: 1, green: 2, blue: 3, alpha: 255)) == nil)
    }

    /// Each colour recolours each kind of annotation as one "Restyle <noun>" step, the selection
    /// reports its ink, and the flattened output equals the preview byte for byte.
    @Test func recolouringIsOneNamedStepAndThePreviewEqualsTheDeliveredImageInEachColour() throws {
        let base = try Self.marked()
        let width = 160, height = 180
        let png = try CaptureRendererTests.encode(CaptureRendererTests.pattern(width: width, height: height),
                                                  width: width, height: height)
        let preview = try CaptureRenderer().preview(png)
        let nouns = ["Shape", "Arrow", "Line", "Label"]
        for (index, noun) in nouns.enumerated() {
            for choice in DocumentAnnotation.palette.dropFirst() {
                let undoManager = UndoManager()
                let editor = MarkEditor(UndoableEdits(base, undoManager: undoManager))
                #expect(editor.selectionInk == nil, "nothing selected")
                editor.select(.annotation(index))
                #expect(editor.selectionInk == DocumentAnnotation.stroke)
                #expect(editor.recolourSelection(choice.pixel), "\(choice.name) \(noun)")
                Self.endEvent(undoManager)
                #expect(undoManager.undoActionName == "Restyle \(noun)")
                #expect(editor.selectionInk == choice.pixel)
                let current = editor.document.edits
                let shown = try previewed(preview, current)
                let delivered = try CaptureRendererTests.decode(try CaptureRenderer().flatten(png, edits: current))
                #expect(delivered.bytes == shown.bytes, "\(choice.name) \(noun): delivered differs from the preview")
                undoManager.undo()
                #expect(editor.document.edits == base, "one undo reverts \(choice.name) \(noun)")
                #expect(!undoManager.canUndo)
            }
        }
    }

    /// Well inside a thick shape's stroke every pixel is exactly the ink, White and Yellow included:
    /// no plate or blend tints the ink.
    @Test func aShapeIsDrawnExactlyInEachInk() throws {
        let width = 120, height = 90
        let png = try CaptureRendererTests.encode(CaptureRendererTests.pattern(width: width, height: height),
                                                  width: width, height: height)
        for choice in DocumentAnnotation.palette {
            let shape = try #require(DocumentAnnotation(.rectangle(x: 4, y: 4, width: 40, height: 30),
                                                        colour: choice.pixel, width: 8))
            let edits = try #require(DocumentEdits(scale: 2, annotations: [shape]))
            let out = try CaptureRendererTests.decode(try CaptureRenderer().flatten(png, edits: edits))
            // The stroke lies inside the box: 16 output pixels wide from (8, 8). Sample its middle.
            for (x, y) in [(16, 40), (40, 16), (80, 40), (40, 60)] {
                let i = (y * width + x) * 4
                #expect(Array(out.bytes[i..<(i + 4)]) == [choice.pixel.red, choice.pixel.green, choice.pixel.blue, 255],
                        "\(choice.name) at (\(x), \(y))")
            }
        }
    }

    /// An Outlined label's letters follow the Box rule (ticket 99): white inside a dark or mid ink,
    /// black inside a light one, so White and Yellow outlines keep their letters readable.
    @Test func anOutlinedLabelInALightInkHasBlackLetters() throws {
        let width = 200, height = 80
        let grey = [UInt8](repeating: 0x80, count: width * height * 4).enumerated().map { $0.offset % 4 == 3 ? 255 : $0.element }
        let png = try CaptureRendererTests.encode(grey, width: width, height: height)
        func count(_ ink: String, _ target: [UInt8]) throws -> Int {
            let pixel = try #require(DocumentAnnotation.palette.first { $0.name == ink }).pixel
            let format = try #require(LabelFormat(style: .outlined, size: 36))
            let label = try #require(DocumentAnnotation(.text(x: 4, y: 4, characters: "HOME"), colour: pixel, label: format))
            let edits = try #require(DocumentEdits(scale: 1, annotations: [label]))
            let out = try CaptureRendererTests.decode(try CaptureRenderer().flatten(png, edits: edits))
            return stride(from: 0, to: out.bytes.count, by: 4).filter { Array(out.bytes[$0..<($0 + 4)]) == target }.count
        }
        let black: [UInt8] = [0, 0, 0, 255], white: [UInt8] = [255, 255, 255, 255]
        for ink in ["White", "Yellow"] {
            #expect(try count(ink, black) > 50, "\(ink): black letters")
        }
        for ink in ["Red", "Blue", "Black"] {
            #expect(try count(ink, white) > 50, "\(ink): white letters")
        }
        #expect(try count("Red", black) == 0, "Red keeps white letters (existing goldens)")
    }

    /// The Text tool's ink applies to the label being typed, as its own "Restyle Label" step.
    @Test func inkRecoloursTheLabelBeingTyped() throws {
        let undoManager = UndoManager()
        let document = UndoableEdits(try #require(DocumentEdits(scale: 2)), undoManager: undoManager)
        let blue = try #require(DocumentAnnotation.palette.first { $0.name == "Blue" }).pixel
        let session = LabelSession(document: document, x: 4, y: 4, colour: blue)
        session.type("Hi")
        Self.endEvent(undoManager)
        #expect(document.edits.annotations.first?.colour == blue, "a new label takes the tool's ink")
        let green = try #require(DocumentAnnotation.palette.first { $0.name == "Green" }).pixel
        session.recolour(green)
        Self.endEvent(undoManager)
        #expect(session.colour == green)
        #expect(document.edits.annotations.first?.colour == green)
        #expect(undoManager.undoActionName == "Restyle Label")
        undoManager.undo()
        #expect(document.edits.annotations.first?.colour == blue)
    }

    @Test func recolouringRefusesAnInkThatIsNotOpaque() throws {
        let editor = MarkEditor(UndoableEdits(try Self.marked(), undoManager: UndoManager()))
        editor.select(.annotation(1))
        #expect(!editor.recolourSelection(RGBAPixel(red: 255, green: 255, blue: 0, alpha: 200)))
    }
}
