import CoreGraphics
import Foundation
import FrisketCore
import Testing

/// Ticket 85: Standard, Curved and Double arrows and the plain Line.
///
/// Tolerance (this ticket's decision): geometry goldens are exact to 1e-9 in the polygons' own units.
/// Pixel goldens compare only pixels at least 1 px inside a polygon (exactly the ink) or at least 2 px
/// outside it, past the 1 px white plate (exactly the base); antialiased edge pixels are not compared.
/// The preview and the delivered image are compared byte for byte.
@MainActor @Suite struct ArrowStylesTests {
    private static let exact = 1e-9
    private static func same(_ a: [[CGPoint]], _ b: [[CGPoint]]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { p, q in
            p.count == q.count && zip(p, q).allSatisfy { abs($0.x - $1.x) <= exact && abs($0.y - $1.y) <= exact }
        }
    }
    private static func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    // MARK: Geometry goldens

    @Test func standardIsATaperedShaftUnderASolidHead() {
        let polygons = ArrowGeometry.polygons(style: .standard, tail: Self.p(0, 0), tip: Self.p(100, 0),
                                              bend: .straight, width: 4, head: 20)
        // The shaft goes from half the width (2) at the tail to 1.5× (6) and ends inside the head.
        #expect(Self.same(polygons, [[Self.p(0, 1), Self.p(90, 3), Self.p(90, -3), Self.p(0, -1)],
                                     [Self.p(100, 0), Self.p(80, 10), Self.p(80, -10)]]), "\(polygons)")
    }

    @Test func doubleHasAHeadAtEachEndAndAnEvenShaft() {
        let polygons = ArrowGeometry.polygons(style: .double, tail: Self.p(0, 0), tip: Self.p(100, 0),
                                              bend: .straight, width: 4, head: 20)
        #expect(Self.same(polygons, [[Self.p(10, 2), Self.p(90, 2), Self.p(90, -2), Self.p(10, -2)],
                                     [Self.p(100, 0), Self.p(80, 10), Self.p(80, -10)],
                                     [Self.p(0, 0), Self.p(20, -10), Self.p(20, 10)]]), "\(polygons)")
    }

    @Test func lineIsAnEvenBarWithSquareEnds() {
        let polygons = ArrowGeometry.polygons(style: .line, tail: Self.p(0, 0), tip: Self.p(10, 0),
                                              bend: .newCurve, width: 2, head: 20)
        #expect(Self.same(polygons, [[Self.p(-1, 1), Self.p(11, 1), Self.p(11, -1), Self.p(-1, -1)]]), "\(polygons)")
    }

    @Test func aShortArrowsHeadShrinksToFit() {
        let polygons = ArrowGeometry.polygons(style: .standard, tail: Self.p(0, 0), tip: Self.p(10, 0),
                                              bend: .straight, width: 2, head: 20)
        #expect(Self.same([polygons[1]], [[Self.p(10, 0), Self.p(4, 3), Self.p(4, -3)]]), "60% of the length: \(polygons)")
    }

    @Test func curvedPassesThroughItsMiddleHandleAndItsHeadFollowsTheTangent() throws {
        let tail = Self.p(0, 0), tip = Self.p(100, 0)
        let bend = ArrowBend.newCurve
        let handle = bend.handle(tail: tail, tip: tip)
        #expect(abs(handle.x - 50) <= Self.exact && abs(handle.y + 20) <= Self.exact, "a fifth of the length: \(handle)")
        let spine = ArrowGeometry.spine(style: .curved, tail: tail, tip: tip, bend: bend)
        let middle = spine[ArrowGeometry.curveSamples / 2]
        #expect(abs(middle.x - handle.x) <= Self.exact && abs(middle.y - handle.y) <= Self.exact)
        #expect(spine.first == tail && spine.last == tip)

        let control = ArrowGeometry.control(tail: tail, tip: tip, bend: bend)
        #expect(abs(control.x - 50) <= Self.exact && abs(control.y + 40) <= Self.exact)
        let head = try #require(ArrowGeometry.polygons(style: .curved, tail: tail, tip: tip, bend: bend,
                                                       width: 4, head: 20).last)
        #expect(head[0] == tip)
        // The head's axis (tip minus the base's midpoint) is the curve's tangent at the tip, tip − control.
        let axis = (x: tip.x - (head[1].x + head[2].x) / 2, y: tip.y - (head[1].y + head[2].y) / 2)
        let tangent = (x: tip.x - control.x, y: tip.y - control.y)
        #expect(abs(axis.x * tangent.y - axis.y * tangent.x) <= 1e-9 * hypot(tangent.x, tangent.y) * 20)
        #expect(abs(hypot(axis.x, axis.y) - 20) <= Self.exact)
    }

    @Test func aBendRoundTripsThroughItsHandle() throws {
        let tail = Self.p(3, 7), tip = Self.p(40, -11)
        let bend = try #require(ArrowBend(along: 0.1, across: 0.35))
        let back = try #require(ArrowBend.through(bend.handle(tail: tail, tip: tip), tail: tail, tip: tip))
        #expect(abs(back.along - 0.1) <= Self.exact && abs(back.across - 0.35) <= Self.exact)
    }

    // MARK: Editing

    private static func editor(_ annotations: [DocumentAnnotation]) throws -> MarkEditor {
        MarkEditor(UndoableEdits(try #require(DocumentEdits(scale: 2, annotations: annotations)), undoManager: UndoManager()))
    }

    @Test func draggingTheMiddleHandleBendsTheArrowAsOneUndoStep() throws {
        let curved = try #require(DocumentAnnotation(.arrow(x0: 10, y0: 60, x1: 110, y1: 60), style: .curved))
        let editor = try Self.editor([curved])
        #expect(editor.click(atX: 60, y: 40, tolerance: 2), "the curve is hit at its middle handle")
        #expect(!editor.click(atX: 60, y: 60, tolerance: 2), "the chord is not the curve")
        editor.select(.annotation(0))
        let handles = try #require(editor.selectionOutline?.handles)
        #expect(handles.map(\.handle) == [.tail, .bend, .tip])
        #expect(handles[1].x == 60 && handles[1].y == 40)

        let grab = try #require(editor.press(atX: 60, y: 40, tolerance: 2, anyMark: false))
        #expect(grab.handle == .bend)
        #expect(editor.release(grab, fromX: 60, fromY: 40, toX: 80, toY: 90))
        let bent = editor.document.edits.annotations[0]
        let moved = bent.bend.handle(tail: Self.p(10, 60), tip: Self.p(110, 60))
        #expect(abs(moved.x - 80) <= Self.exact && abs(moved.y - 90) <= Self.exact, "the handle follows the pointer")
        #expect(editor.document.undoManager.undoActionName == "Resize Arrow")
        #expect(editor.document.edits.bounds(of: .annotation(0)).map { $0.y + $0.height } ?? 0 > 89,
                "the bounds follow the curve")

        // Moving and dragging an end keep the shape relative to the chord.
        editor.nudge(dx: 5, dy: 5)
        #expect(editor.document.edits.annotations[0].bend == bent.bend)
        let tip = try #require(editor.press(atX: 115, y: 65, tolerance: 2, anyMark: false))
        #expect(tip.handle == .tip)
        editor.release(tip, fromX: 115, fromY: 65, toX: 215, toY: 65)
        #expect(editor.document.edits.annotations[0].bend == bent.bend)
    }

    @Test func aStraightArrowHasNoMiddleHandleAndRefusesABend() throws {
        let editor = try Self.editor([try #require(DocumentAnnotation(.arrow(x0: 10, y0: 60, x1: 110, y1: 60)))])
        editor.select(.annotation(0))
        #expect(editor.selectionOutline?.handles.map(\.handle) == [.tail, .tip])
        #expect(editor.document.edits.applying(.resize(.bend, x: 60, y: 20), to: .annotation(0)) == nil)
    }

    @Test func restylingAnArrowIsOneStepAndNamesTheMark() throws {
        let shape = try #require(DocumentAnnotation(.rectangle(x: 0, y: 0, width: 10, height: 10)))
        let arrow = try #require(DocumentAnnotation(.arrow(x0: 2, y0: 38, x1: 38, y1: 38)))
        let editor = try Self.editor([shape, arrow])
        editor.select(.annotation(1))
        #expect(editor.selectionStyle == .standard)
        #expect(editor.restyleSelection(.curved))
        #expect(editor.document.edits.annotations[1].bend == .newCurve, "a new curve bows by a fifth")
        #expect(editor.document.undoManager.undoActionName == "Restyle Arrow")
        #expect(editor.document.edits.accessibilityLabel(for: .annotation(1)) == "Curved arrow from 2, 38 to 38, 38")
        #expect(editor.restyleSelection(.double))
        #expect(editor.document.edits.annotations[1].bend == .straight)
        #expect(editor.document.edits.accessibilityLabel(for: .annotation(1)) == "Double arrow from 2, 38 to 38, 38")
        #expect(editor.restyleSelection(.line))
        #expect(editor.document.edits.noun(for: .annotation(1)) == "Line")
        #expect(editor.document.edits.accessibilityLabel(for: .annotation(1)) == "Line from 2, 38 to 38, 38")
        #expect(!editor.restyleSelection(.line), "the same style changes nothing")
        editor.select(.annotation(0))
        #expect(editor.selectionStyle == nil)
        #expect(!editor.restyleSelection(.curved), "a shape has no arrow style")
    }

    @Test func aNewLineIsNamedLineInTheUndoMenu() throws {
        let document = UndoableEdits(try #require(DocumentEdits(scale: 1)), undoManager: UndoManager())
        var next = document.edits
        next.annotations.append(try #require(DocumentAnnotation(.arrow(x0: 0, y0: 0, x1: 9, y1: 9), style: .line)))
        document.apply(next)
        #expect(document.undoManager.undoActionName == "Line")
    }

    // MARK: Pixel goldens and parity

    private static let base = RGBAPixel(red: 0x20, green: 0x40, blue: 0x60, alpha: 0xff)
    private static let ink = DocumentAnnotation.stroke

    private static func rendered(_ annotation: DocumentAnnotation, width: Int = 130, height: Int = 80) throws -> Picture {
        let bytes = (0..<(width * height)).flatMap { _ in [base.red, base.green, base.blue, base.alpha] }
        let png = try CaptureRendererTests.encode(bytes, width: width, height: height)
        return try delivered(png, try #require(DocumentEdits(scale: 1, annotations: [annotation])))
    }

    private static func inkRows(_ picture: Picture, column: Int) -> Int {
        (0..<picture.height).filter { picture.pixel(x: column, y: $0) == ink }.count
    }

    @Test func standardPixelsTaperTowardsASolidHead() throws {
        // 4 pt at 1×: head 18 px long, 9 px each side; the shaft ends 9 px inside it.
        let picture = try Self.rendered(try #require(DocumentAnnotation(.arrow(x0: 0, y0: 20, x1: 100, y1: 20), width: 4)))
        #expect(Self.inkRows(picture, column: 5) == 2, "about 2 px wide near the tail")
        #expect(Self.inkRows(picture, column: 80) == 4, "about 5.5 px wide near the head")
        for (x, y) in [(90, 20), (88, 17), (88, 23), (85, 14), (85, 25)] {
            #expect(picture.pixel(x: x, y: y) == Self.ink, "the head is solid at \(x), \(y)")
        }
        for (x, y) in [(85, 9), (85, 31), (103, 20), (50, 15), (50, 25)] {
            #expect(picture.pixel(x: x, y: y) == Self.base, "outside at \(x), \(y)")
        }
    }

    @Test func doubleHasSolidHeadsAtBothEndsAndLineHasNone() throws {
        let double = try Self.rendered(try #require(DocumentAnnotation(.arrow(x0: 10, y0: 20, x1: 110, y1: 20), width: 4,
                                                                       style: .double)))
        let standard = try Self.rendered(try #require(DocumentAnnotation(.arrow(x0: 10, y0: 20, x1: 110, y1: 20), width: 4)))
        #expect(double.pixel(x: 18, y: 17) == Self.ink, "a head at the tail")
        #expect(standard.pixel(x: 18, y: 17) != Self.ink, "no head at a Standard arrow's tail")
        #expect(double.pixel(x: 102, y: 17) == Self.ink && standard.pixel(x: 102, y: 17) == Self.ink)
        #expect(Self.inkRows(double, column: 60) == 4)

        let line = try Self.rendered(try #require(DocumentAnnotation(.arrow(x0: 10, y0: 20, x1: 110, y1: 20), width: 4,
                                                                     style: .line)))
        #expect(Self.inkRows(line, column: 15) == 4 && Self.inkRows(line, column: 105) == 4, "an even 4 px")
        #expect(line.pixel(x: 111, y: 20) == Self.ink, "a square end 2 px past the tip")
        #expect(line.pixel(x: 114, y: 20) == Self.base)
        #expect(line.pixel(x: 105, y: 16) == Self.base, "no head")
    }

    @Test func curvedPixelsFollowTheCurveNotTheChord() throws {
        let picture = try Self.rendered(try #require(DocumentAnnotation(.arrow(x0: 10, y0: 60, x1: 110, y1: 60), width: 4,
                                                                        style: .curved)))
        #expect(picture.pixel(x: 60, y: 40) == Self.ink, "the middle handle is on the curve, 20 px above the chord")
        #expect(picture.pixel(x: 60, y: 60) == Self.base)
        #expect(picture.pixel(x: 60, y: 45) == Self.base && picture.pixel(x: 60, y: 35) == Self.base)
    }

    /// Delivered image = editor preview, for every style, at 1× and 2×, with a crop.
    @Test(arguments: [1.0, 2.0])
    func everyStyleRendersTheSameInThePreviewAndTheSavedOutput(scale: Double) throws {
        let width = 240, height = 180
        let png = try CaptureRendererTests.encode(CaptureRendererTests.pattern(width: width, height: height),
                                                  width: width, height: height)
        let preview = try CaptureRenderer().preview(png)
        let bend = try #require(ArrowBend(along: 0.15, across: 0.4))
        let redaction = try #require(SolidRedaction(x: 30, y: 30, width: 20, height: 12))
        for style in ArrowStyle.allCases {
            for width in DocumentAnnotation.lineWidths {
                let arrow = try #require(DocumentAnnotation(.arrow(x0: 12.3, y0: 70.6, x1: 95.2, y1: 22.1),
                                                            width: width, style: style, bend: bend))
                let short = try #require(DocumentAnnotation(.arrow(x0: 40, y0: 40, x1: 44, y1: 37), width: width, style: style))
                let crop = try #require(DocumentCrop(x: 2.5, y: 1.25, width: 100, height: 80))
                let edits = try #require(DocumentEdits(scale: scale, crop: crop, redactions: [redaction],
                                                       annotations: [arrow, short]))
                let saved = try delivered(png, edits)
                let shown = try previewed(preview, edits)
                #expect(saved.bytes == shown.bytes, "\(style) at \(width) pt, \(scale)×")
                // The redaction stays the chosen colour at alpha 255 under the arrows' plates.
                let x0 = Int(((30 - 2.5) * scale).rounded(.down)), y0 = Int(((30 - 1.25) * scale).rounded(.down))
                #expect(saved.pixel(x: x0 + 1, y: y0 + 1) == SolidRedaction.fill)
            }
        }
    }
}
