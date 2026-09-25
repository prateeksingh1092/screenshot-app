import Foundation
import FrisketCore
import Testing

/// Ticket 84: a mark stays an object after drawing. It is selected with a click, moved, resized,
/// deleted and restyled; each change is one undo step, and the delivered image equals the preview
/// after every edit.
@MainActor @Suite struct EditableMarksTests {
    /// Closes the current event's undo group, as the run loop does after a mouse-up or key press.
    private static func endEvent(_ undoManager: UndoManager) {
        #expect(undoManager.groupingLevel == 1, "each change opens exactly one event group")
        RunLoop.main.add(Timer(timeInterval: 0.001, repeats: false) { _ in }, forMode: .default)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        #expect(undoManager.groupingLevel == 0)
    }

    /// One of each mark: redaction, blur, magnify, shape, arrow and label.
    private static func marked() throws -> DocumentEdits {
        let redaction = try #require(SolidRedaction(x: 4, y: 4, width: 10, height: 8))
        let shape = try #require(DocumentAnnotation(.rectangle(x: 30, y: 4, width: 20, height: 16)))
        let arrow = try #require(DocumentAnnotation(.arrow(x0: 4, y0: 40, x1: 40, y1: 40)))
        let label = try #require(DocumentAnnotation(.text(x: 4, y: 50, characters: "Hi")))
        let blur = try #require(DocumentEffect(.blur(x: 20, y: 30, width: 8, height: 6)))
        let magnify = try #require(DocumentEffect(.magnify(x: 50, y: 30, width: 8, height: 6)))
        return try #require(DocumentEdits(scale: 2, redactions: [redaction], annotations: [shape, arrow, label],
                                          effects: [blur, magnify]))
    }

    private static func editor(_ edits: DocumentEdits) -> (MarkEditor, UndoManager) {
        let undoManager = UndoManager()
        return (MarkEditor(UndoableEdits(edits, undoManager: undoManager)), undoManager)
    }

    @Test func clickingAMarkSelectsItAndAClickElsewhereOrEscDeselects() throws {
        let (editor, _) = Self.editor(try Self.marked())
        #expect(editor.click(atX: 8, y: 8, tolerance: 2))
        #expect(editor.selection == .redaction(0))
        #expect(editor.selectionOutline?.handles.count == 4, "a box shows four corner handles")

        #expect(editor.click(atX: 20, y: 40.5, tolerance: 2), "the arrow's line is hit")
        #expect(editor.selection == .annotation(1))
        #expect(editor.selectionOutline?.handles.map(\.handle) == [.tail, .tip])

        #expect(!editor.click(atX: 40, y: 12, tolerance: 1), "inside a shape's outline is not the shape")
        #expect(editor.selection == nil)

        editor.select(.annotation(2))
        #expect(editor.deselect(), "Esc deselects")
        #expect(!editor.deselect(), "a second Esc is the window's")
    }

    @Test func theTopmostMarkIsSelected() throws {
        var edits = try Self.marked()
        edits.annotations.append(try #require(DocumentAnnotation(.arrow(x0: 0, y0: 8, x1: 20, y1: 8))))
        let (editor, _) = Self.editor(edits)
        editor.click(atX: 8, y: 8, tolerance: 1)
        #expect(editor.selection == .annotation(3), "the arrow drawn over the redaction")
    }

    @Test func moveResizeDeleteAndRestyleAreEachOneNamedUndoStep() throws {
        let base = try Self.marked()
        let red = RGBAPixel(red: 0, green: 0x7a, blue: 0xff, alpha: 255)
        let steps: [(name: String, act: (MarkEditor) -> Bool, check: (DocumentEdits) -> Bool)] = [
            ("Move Solid Redaction", { e in
                e.select(.redaction(0))
                guard let grab = e.press(atX: 8, y: 8, tolerance: 2, anyMark: false) else { return false }
                return e.release(grab, fromX: 8, fromY: 8, toX: 11, toY: 6)
            }, { $0.redactions[0] == SolidRedaction(x: 7, y: 2, width: 10, height: 8) }),
            ("Resize Shape", { e in
                e.select(.annotation(0))
                guard let grab = e.press(atX: 50, y: 20, tolerance: 2, anyMark: false), grab.handle == .bottomRight
                else { return false }
                return e.release(grab, fromX: 50, fromY: 20, toX: 60, toY: 30)
            }, { $0.annotations[0].kind == .rectangle(x: 30, y: 4, width: 30, height: 26) }),
            ("Resize Arrow", { e in
                e.select(.annotation(1))
                guard let grab = e.press(atX: 40, y: 40, tolerance: 2, anyMark: false), grab.handle == .tip
                else { return false }
                return e.release(grab, fromX: 40, fromY: 40, toX: 44, toY: 60)
            }, { $0.annotations[1].kind == .arrow(x0: 4, y0: 40, x1: 44, y1: 60) }),
            ("Move Label", { e in
                e.select(.annotation(2))
                return e.nudge(dx: 1, dy: 0)
            }, { $0.annotations[2].kind == .text(x: 5, y: 50, characters: "Hi") }),
            ("Resize Blur", { e in
                e.select(.effect(0))
                guard let grab = e.press(atX: 20, y: 30, tolerance: 2, anyMark: false), grab.handle == .topLeft
                else { return false }
                return e.release(grab, fromX: 20, fromY: 30, toX: 18, toY: 28)
            }, { $0.effects[0].kind == .blur(x: 18, y: 28, width: 10, height: 8) }),
            ("Delete Magnify", { e in
                e.select(.effect(1))
                return e.deleteSelection() && e.selection == nil
            }, { $0.effects.count == 1 }),
            ("Restyle Arrow", { e in
                e.select(.annotation(1))
                return e.recolourSelection(red)
            }, { $0.annotations[1].colour == red && $0.annotations[1].width == 2 }),
            ("Restyle Shape", { e in
                e.select(.annotation(0))
                return e.rewidthSelection(8)
            }, { $0.annotations[0].width == 8 && $0.annotations[0].colour == DocumentAnnotation.stroke })
        ]
        for step in steps {
            let (editor, undoManager) = Self.editor(base)
            #expect(step.act(editor), "\(step.name) applies")
            Self.endEvent(undoManager)
            #expect(step.check(editor.document.edits), "\(step.name) changes the mark")
            #expect(undoManager.undoActionName == step.name)
            undoManager.undo()
            #expect(editor.document.edits == base, "one undo reverts \(step.name)")
            #expect(!undoManager.canUndo, "\(step.name) is exactly one step")
            undoManager.redo()
            #expect(step.check(editor.document.edits), "\(step.name) redoes")
        }
    }

    @Test func aChangeThatWouldEmptyOrMisstyleAMarkIsRefused() throws {
        let (editor, undoManager) = Self.editor(try Self.marked())
        editor.select(.annotation(0))
        guard let grab = editor.press(atX: 50, y: 20, tolerance: 2, anyMark: false) else {
            Issue.record("no handle"); return
        }
        #expect(!editor.release(grab, fromX: 50, fromY: 20, toX: 30, toY: 20), "a zero-height shape")
        editor.select(.annotation(2))
        #expect(!editor.rewidthSelection(4), "a label has no line width")
        editor.select(.redaction(0))
        #expect(!editor.rewidthSelection(4), "a Solid redaction has no line width")
        #expect(!editor.recolourSelection(RGBAPixel(red: 0, green: 0, blue: 0, alpha: 128)),
                "a Solid redaction stays alpha 255 (decision 61)")
        #expect(!undoManager.canUndo, "nothing was registered")
    }

    @Test func aSolidRedactionKeepsItsColourWhenMovedAndRecoloursOnlyOpaque() throws {
        let grey = RGBAPixel(red: 0x80, green: 0x80, blue: 0x80, alpha: 255)
        var edits = try Self.marked()
        edits.redactions[0] = try #require(SolidRedaction(x: 4, y: 4, width: 10, height: 8, colour: grey))
        let (editor, _) = Self.editor(edits)
        editor.select(.redaction(0))
        #expect(editor.nudge(dx: 0, dy: 1))
        #expect(editor.document.edits.redactions[0].colour == grey)
        #expect(editor.recolourSelection(SolidRedaction.fill))
        #expect(editor.document.edits.redactions[0].colour == SolidRedaction.fill)
    }

    /// Ticket 88 (decision 61): a small palette of neutral colours, black first as the default,
    /// every one fully opaque. There is no free colour picker.
    @Test func theRedactionPaletteIsSmallNeutralOpaqueAndStartsWithBlack() {
        let palette = SolidRedaction.palette
        #expect(palette.first?.pixel == SolidRedaction.fill, "black is the default")
        #expect((3...6).contains(palette.count))
        #expect(palette.allSatisfy { $0.pixel.alpha == 255 }, "every fill is opaque")
        #expect(palette.allSatisfy { $0.pixel.red == $0.pixel.green && $0.pixel.green == $0.pixel.blue }, "neutral colours only")
        #expect(palette.contains { $0.pixel == RGBAPixel(red: 255, green: 255, blue: 255, alpha: 255) }, "white is offered")
        #expect(Set(palette.map(\.name)).count == palette.count && Set(palette.map(\.pixel)).count == palette.count)
    }

    /// Ticket 88: the palette recolours a selected Solid redaction; each choice is one "Restyle" step,
    /// and every covered pixel of the flattened output is exactly that colour at alpha 255.
    @Test func thePaletteRecoloursASelectedRedactionExactly() throws {
        let (editor, undoManager) = Self.editor(try Self.marked())
        #expect(editor.selectionFill == nil, "nothing selected")
        editor.select(.annotation(0))
        #expect(editor.selectionFill == nil, "a shape has no fill")
        editor.select(.redaction(0))
        #expect(editor.selectionFill == SolidRedaction.fill)
        let width = 80, height = 64
        let png = try CaptureRendererTests.encode(CaptureRendererTests.pattern(width: width, height: height),
                                                  width: width, height: height)
        for choice in SolidRedaction.palette.dropFirst() {
            #expect(editor.recolourSelection(choice.pixel), "\(choice.name) applies")
            Self.endEvent(undoManager)
            #expect(undoManager.undoActionName == "Restyle Solid Redaction")
            #expect(editor.selectionFill == choice.pixel)
            let out = try CaptureRendererTests.decode(try CaptureRenderer().flatten(png, edits: editor.document.edits))
            // The redaction is 4, 4, 10 × 8 points at scale 2.
            for y in 8..<24 {
                for x in 8..<28 {
                    let i = (y * width + x) * 4
                    #expect(Array(out.bytes[i..<(i + 4)]) == [choice.pixel.red, choice.pixel.green, choice.pixel.blue, 255],
                            "\(choice.name): pixel (\(x), \(y))")
                }
            }
        }
    }

    @Test func keyboardTabsThroughMarksInPaintOrderThenLeaves() throws {
        let (editor, _) = Self.editor(try Self.marked())
        var visited: [MarkReference] = []
        while editor.selectNext() { visited.append(try #require(editor.selection)) }
        #expect(visited == [.redaction(0), .effect(0), .effect(1), .annotation(0), .annotation(1), .annotation(2)])
        #expect(editor.selection == nil, "Tab past the last mark leaves the canvas")
        #expect(editor.selectNext(backward: true))
        #expect(editor.selection == .annotation(2), "Shift-Tab starts from the last mark")
    }

    @Test func everyMarkHasAVoiceOverLabelRelativeToTheCrop() throws {
        var edits = try Self.marked()
        edits.crop = try #require(DocumentCrop(x: 2, y: 2, width: 60, height: 60))
        let (editor, _) = Self.editor(edits)
        let marks = editor.accessibleMarks
        #expect(marks.count == 6)
        #expect(marks.allSatisfy { !$0.label.isEmpty })
        #expect(marks[0].label.hasPrefix("Solid redaction, 10 by 8 points at 2, 2"))
        #expect(marks[1].label.contains("Does not hide pixels"))
        #expect(marks[4].label == "Arrow from 2, 38 to 38, 38")
        #expect(marks[5].label.hasPrefix("Label, Hi"))
        #expect(marks[0].box == MarkBox(x: 2, y: 2, width: 10, height: 8), "boxes are in canvas points")
    }

    @Test func pressesOnACroppedCanvasReachTheMarkUnderThePointer() throws {
        var edits = try Self.marked()
        edits.crop = try #require(DocumentCrop(x: 2, y: 2, width: 60, height: 60))
        let (editor, _) = Self.editor(edits)
        let grab = try #require(editor.press(atX: 6, y: 6, tolerance: 1, anyMark: true), "the Select tool takes any mark")
        #expect(grab == MarkEditor.Grab(mark: .redaction(0), handle: nil))
        #expect(editor.selection == .redaction(0))
        #expect(editor.release(grab, fromX: 6, fromY: 6, toX: 8, toY: 6))
        #expect(editor.document.edits.redactions[0].x == 6)
        #expect(editor.press(atX: 40, y: 50, tolerance: 1, anyMark: false) == nil, "a drawing tool draws off the selection")
    }

    /// The saved output equals the preview after every edit (ticket 68's parity).
    @Test func theDeliveredImageEqualsThePreviewAfterEveryMarkEdit() throws {
        let width = 160, height = 140
        let png = try CaptureRendererTests.encode(CaptureRendererTests.pattern(width: width, height: height),
                                                  width: width, height: height)
        let preview = try CaptureRenderer().preview(png)
        let (editor, _) = Self.editor(try Self.marked())
        let blue = RGBAPixel(red: 0, green: 0x7a, blue: 0xff, alpha: 255)
        let edits: [(MarkEditor) -> Bool] = [
            { $0.select(.annotation(1)); return $0.nudge(dx: 3.5, dy: -2) },
            { $0.rewidthSelection(8) },
            { $0.recolourSelection(blue) },
            { e in
                guard let grab = e.press(atX: 7.5, y: 38, tolerance: 2, anyMark: false) else { return false }
                return e.release(grab, fromX: 7.5, fromY: 38, toX: 12, toY: 60)
            },
            { $0.select(.annotation(0)); return $0.rewidthSelection(4) },
            { $0.select(.redaction(0)); return $0.nudge(dx: 60, dy: 0.5) },
            { $0.select(.effect(0)); return $0.nudge(dx: -5, dy: 5) },
            { $0.select(.annotation(2)); return $0.recolourSelection(blue) },
            { $0.select(.effect(1)); return $0.deleteSelection() }
        ]
        for (step, edit) in edits.enumerated() {
            #expect(edit(editor), "edit \(step) applies")
            let current = editor.document.edits
            let shown = try previewed(preview, current)
            let delivered = try CaptureRendererTests.decode(try CaptureRenderer().flatten(png, edits: current))
            #expect(delivered.bytes == shown.bytes, "edit \(step): the delivered image differs from the preview")
            // Every redacted pixel stays exactly its colour (no ink crosses this redaction).
            let r = current.redactions[0]
            for y in Int(r.y * 2)..<Int((r.y + r.height) * 2) where y < height {
                for x in Int(r.x * 2)..<Int((r.x + r.width) * 2) where x < width {
                    let i = (y * width + x) * 4
                    #expect(Array(delivered.bytes[i..<i + 4]) == [0, 0, 0, 255], "edit \(step): pixel \(x), \(y)")
                }
            }
        }
    }

    @Test func aWiderOrRecolouredArrowIsDrawnInItsInk() throws {
        let width = 80, height = 40
        let png = try CaptureRendererTests.encode([UInt8](repeating: 255, count: width * height * 4), width: width, height: height)
        let green = RGBAPixel(red: 0, green: 0xc0, blue: 0x40, alpha: 255)
        func inkRows(_ annotation: DocumentAnnotation, _ ink: RGBAPixel) throws -> Int {
            let edits = try #require(DocumentEdits(scale: 1, annotations: [annotation]))
            let out = try CaptureRendererTests.decode(try CaptureRenderer().flatten(png, edits: edits))
            return (0..<height).filter { y in
                let i = (y * width + 10) * 4
                return Array(out.bytes[i..<i + 4]) == [ink.red, ink.green, ink.blue, 255]
            }.count
        }
        // A Line keeps an even width; a Standard arrow tapers (ticket 85, `ArrowStylesTests`).
        let thin = try inkRows(try #require(DocumentAnnotation(.arrow(x0: 2, y0: 20, x1: 70, y1: 20), style: .line)), DocumentAnnotation.stroke)
        let thick = try inkRows(try #require(DocumentAnnotation(.arrow(x0: 2, y0: 20, x1: 70, y1: 20), colour: green, width: 8,
                                                                style: .line)), green)
        #expect(thin == 2)
        #expect(thick == 8)
    }

    @Test func canvasKeysMapToMarkActions() {
        #expect(MarkKey.action(characters: "\t", shift: false) == .next)
        #expect(MarkKey.action(characters: "\t", shift: true) == .previous)
        #expect(MarkKey.action(characters: "\u{19}", shift: true) == .previous)
        #expect(MarkKey.action(characters: "\u{7f}", shift: false) == .delete)
        #expect(MarkKey.action(characters: "\u{F728}", shift: false) == .delete)
        #expect(MarkKey.action(characters: "\u{F703}", shift: false) == .nudge(dx: 1, dy: 0))
        #expect(MarkKey.action(characters: "\u{F700}", shift: true) == .nudge(dx: 0, dy: -10))
        #expect(MarkKey.action(characters: "a", shift: false) == nil, "letters stay tool keys")
    }

    @Test func aPressWithoutADragChangesNothing() throws {
        let (editor, undoManager) = Self.editor(try Self.marked())
        let grab = try #require(editor.press(atX: 8, y: 8, tolerance: 2, anyMark: true))
        #expect(!editor.release(grab, fromX: 8, fromY: 8, toX: 8.3, toY: 8, slop: 1))
        #expect(!undoManager.canUndo)
    }
}
