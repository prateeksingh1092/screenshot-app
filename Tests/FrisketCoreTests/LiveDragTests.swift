import Foundation
import FrisketCore
import Testing

/// Ticket 97: while a mark is dragged, the canvas shows it as it will be saved. At every drag point
/// the provisional edits are exactly what mouse-up would commit; they touch neither the edits nor
/// the undo history, and they render through the same preview path as Done.
@MainActor @Suite struct LiveDragTests {
    /// One of each mark, with a Curved arrow and a Grey redaction.
    private static func marked() throws -> DocumentEdits {
        let grey = SolidRedaction.palette[2].pixel
        let redaction = try #require(SolidRedaction(x: 4, y: 4, width: 10, height: 8, colour: grey))
        let shape = try #require(DocumentAnnotation(.rectangle(x: 30, y: 4, width: 20, height: 16), width: 4))
        let arrow = try #require(DocumentAnnotation(.arrow(x0: 4, y0: 40, x1: 40, y1: 40), width: 4, style: .curved))
        let label = try #require(DocumentAnnotation(.text(x: 4, y: 50, characters: "Hi")))
        let blur = try #require(DocumentEffect(.blur(x: 20, y: 30, width: 8, height: 6)))
        return try #require(DocumentEdits(scale: 2, redactions: [redaction], annotations: [shape, arrow, label],
                                          effects: [blur]))
    }

    /// A drag path from `start`: small steps first (inside the click slop), then away and back.
    private static func path(from start: (x: Double, y: Double)) -> [(x: Double, y: Double)] {
        [(0.2, 0.1), (0.9, 0.4), (3, -1.5), (7.25, 2.5), (12, 9), (5, 14), (-3, 6), (0, 0)]
            .map { (start.x + $0.0, start.y + $0.1) }
    }

    /// Every kind of grab: a move of each mark, a corner, an arrow's tip and bend, a label's wrap and
    /// corner handles.
    private static let grabs: [(mark: MarkReference, x: Double, y: Double, handle: MarkHandle?)] = [
        (.redaction(0), 8, 8, nil),
        (.redaction(0), 14, 12, .bottomRight),
        (.effect(0), 24, 33, nil),
        (.annotation(0), 30, 4, .topLeft),
        (.annotation(0), 40, 5, nil),
        (.annotation(1), 40, 40, .tip),
        (.annotation(1), 4, 40, .tail),
        (.annotation(2), 6, 55, nil),
    ]

    @Test func provisionalEditsAtEachDragPointEqualWhatMouseUpCommits() throws {
        let base = try Self.marked()
        var grabs = Self.grabs
        let bend = try #require(base.handles(of: .annotation(1)).first { $0.handle == .bend })
        grabs.append((.annotation(1), bend.x, bend.y, .bend))
        let trailing = try #require(base.handles(of: .annotation(2)).first { $0.handle == .trailing })
        grabs.append((.annotation(2), trailing.x, trailing.y, .trailing))
        let corner = try #require(base.handles(of: .annotation(2)).first { $0.handle == .bottomRight })
        grabs.append((.annotation(2), corner.x, corner.y, .bottomRight))
        let slop = 0.5
        for grabbed in grabs {
            let undoManager = UndoManager()
            let live = MarkEditor(UndoableEdits(base, undoManager: undoManager))
            live.select(grabbed.mark)
            let grab = try #require(live.press(atX: grabbed.x, y: grabbed.y, tolerance: 1, anyMark: false),
                                    "\(grabbed) is held")
            #expect(grab == MarkEditor.Grab(mark: grabbed.mark, handle: grabbed.handle), "\(grabbed)")
            for point in Self.path(from: (grabbed.x, grabbed.y)) {
                let provisional = live.provisional(grab, fromX: grabbed.x, fromY: grabbed.y, toX: point.x, toY: point.y,
                                                   slop: slop)
                #expect(live.document.edits == base, "\(grabbed) at \(point): a provisional edit commits nothing")
                #expect(!undoManager.canUndo, "\(grabbed) at \(point): nor registers an undo step")
                // What mouse-up here would commit, on a fresh editor.
                let committing = MarkEditor(UndoableEdits(base, undoManager: UndoManager()))
                committing.select(grabbed.mark)
                let changed = committing.release(grab, fromX: grabbed.x, fromY: grabbed.y, toX: point.x, toY: point.y,
                                                 slop: slop)
                #expect(provisional == (changed ? committing.document.edits : nil), "\(grabbed) at \(point)")
                if let provisional {
                    // The outline follows the provisional mark, not the committed one.
                    #expect(live.selectionOutline(in: provisional)?.box == committing.selectionOutline?.box,
                            "\(grabbed) at \(point): outline")
                }
            }
        }
    }

    @Test func aWholeDragIsOneUndoStepAfterLiveFeedback() throws {
        let base = try Self.marked()
        let undoManager = UndoManager()
        let editor = MarkEditor(UndoableEdits(base, undoManager: undoManager))
        editor.select(.annotation(1))
        let grab = try #require(editor.press(atX: 40, y: 40, tolerance: 1, anyMark: false))
        for point in Self.path(from: (40, 40)) {
            _ = editor.provisional(grab, fromX: 40, fromY: 40, toX: point.x, toY: point.y)
        }
        #expect(editor.release(grab, fromX: 40, fromY: 40, toX: 52, toY: 49))
        #expect(undoManager.groupingLevel == 1, "the drag opened exactly one event group")
        // The run loop closes the event's group, as it does after a real mouse-up.
        RunLoop.main.add(Timer(timeInterval: 0.001, repeats: false) { _ in }, forMode: .default)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        #expect(undoManager.groupingLevel == 0)
        #expect(undoManager.undoActionName == "Resize Arrow")
        undoManager.undo()
        #expect(editor.document.edits == base, "one undo removes the whole drag")
        #expect(!undoManager.canUndo)
    }

    /// The provisional edits render through `CapturePreview.render`, byte for byte what Done
    /// delivers for the same point, with the moving redaction exactly its chosen colour.
    @Test func theProvisionalPreviewIsTheDeliveredImage() throws {
        let width = 160, height = 140
        let png = try CaptureRendererTests.encode(CaptureRendererTests.pattern(width: width, height: height),
                                                  width: width, height: height)
        let preview = try CaptureRenderer().preview(png)
        #expect(!preview.isDownscaled)
        let base = try Self.marked()
        let grey = SolidRedaction.palette[2].pixel
        for grabbed in Self.grabs {
            let editor = MarkEditor(UndoableEdits(base, undoManager: UndoManager()))
            editor.select(grabbed.mark)
            let grab = try #require(editor.press(atX: grabbed.x, y: grabbed.y, tolerance: 1, anyMark: false))
            for point in Self.path(from: (grabbed.x, grabbed.y)).suffix(4).dropLast() {
                let edits = try #require(editor.provisional(grab, fromX: grabbed.x, fromY: grabbed.y,
                                                            toX: point.x, toY: point.y))
                let shown = try previewed(preview, edits)
                let delivered = try CaptureRendererTests.decode(try CaptureRenderer().flatten(png, edits: edits))
                #expect(shown.bytes == delivered.bytes, "\(grabbed) at \(point): preview differs from delivery")
                let r = edits.redactions[0]
                for y in Int(r.y * 2)..<min(height, Int((r.y + r.height) * 2)) {
                    for x in Int(r.x * 2)..<min(width, Int((r.x + r.width) * 2)) {
                        let i = (y * width + x) * 4
                        #expect(Array(shown.bytes[i..<i + 4]) == [grey.red, grey.green, grey.blue, 255],
                                "\(grabbed) at \(point): redacted pixel \(x), \(y)")
                    }
                }
            }
        }
    }
}
