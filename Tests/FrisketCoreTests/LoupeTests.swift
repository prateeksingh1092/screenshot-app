import Foundation
import FrisketCore
import Testing

/// D26: the Loupe's pure geometry. Which device pixels it samples, and where it sits.
@Suite struct LoupeTests {
    private let retina = SelectionDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    private let external = SelectionDisplay(id: 2, frame: CGRect(x: -1920, y: -180, width: 1920, height: 1080), scale: 1)
    private let size = CGSize(width: 124, height: 124)

    @Test func samplesTheDevicePixelSquareCentredOnThePointersPixel() throws {
        // A pointer names the top-left corner of the pixel under it (D14).
        let sharp = try #require(Loupe.sample(at: CGPoint(x: 100, y: 800), on: retina))
        #expect(sharp == LoupeSample(displayID: 1, scale: 2, left: 193, top: 193, span: 15, column: 7, row: 7))
        #expect(sharp.sourceRect == CGRect(x: 96.5, y: 96.5, width: 7.5, height: 7.5))
        let halfPoint = try #require(Loupe.sample(at: CGPoint(x: 100.5, y: 799.5), on: retina))
        #expect(halfPoint.left + halfPoint.column == 201 && halfPoint.top + halfPoint.row == 201)

        let plain = try #require(Loupe.sample(at: CGPoint(x: -1820, y: 800), on: external))
        #expect(plain == LoupeSample(displayID: 2, scale: 1, left: 93, top: 93, span: 15, column: 7, row: 7))
        #expect(plain.sourceRect == CGRect(x: 93, y: 93, width: 15, height: 15))
    }

    @Test func nearAnEdgeTheSquareStaysOnTheDisplayAndTheMarkMovesOffCentre() throws {
        let topRight = try #require(Loupe.sample(at: CGPoint(x: 1439.5, y: 900), on: retina))
        #expect(topRight == LoupeSample(displayID: 1, scale: 2, left: 2865, top: 0, span: 15, column: 14, row: 0))
        // The bottom-left pixel of a display with a negative origin.
        let bottomLeft = try #require(Loupe.sample(at: CGPoint(x: -1920, y: -179), on: external))
        #expect(bottomLeft == LoupeSample(displayID: 2, scale: 1, left: 0, top: 1065, span: 15, column: 0, row: 14))
    }

    @Test(arguments: [1.0, 2.0]) func everyPointerOnTheDisplayGetsAWholeSquareMarkingItsOwnPixel(scale: Double) throws {
        let display = SelectionDisplay(id: 3, frame: CGRect(x: 0, y: 0, width: 200, height: 120), scale: scale)
        let step = 1 / scale
        var x = 0.0
        while x < 200 {
            var y = step
            while y <= 120 {
                let sample = try #require(Loupe.sample(at: CGPoint(x: x, y: y), on: display))
                #expect(sample.span == 15)
                #expect(sample.left >= 0 && sample.top >= 0)
                #expect(sample.left + 15 <= Int(200 * scale) && sample.top + 15 <= Int(120 * scale))
                #expect(sample.left + sample.column == Int((x * scale).rounded()))
                #expect(sample.top + sample.row == Int(((120 - y) * scale).rounded()))
                y += step * 7
            }
            x += step * 7
        }
    }

    @Test func sitsAboveAndRightOfThePointerAndFlipsAwayFromEdges() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(Loupe.frame(size: size, beside: CGPoint(x: 700, y: 400), in: bounds)
            == CGRect(x: 720, y: 420, width: 124, height: 124))
        #expect(Loupe.frame(size: size, beside: CGPoint(x: 1440, y: 900), in: bounds)
            == CGRect(x: 1296, y: 756, width: 124, height: 124))
        #expect(Loupe.frame(size: size, beside: CGPoint(x: 1400, y: 10), in: bounds)
            == CGRect(x: 1256, y: 30, width: 124, height: 124))
    }

    @Test func neverLeavesTheDisplayOrCoversThePointer() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for x in stride(from: 0.0, through: 1440, by: 12) {
            for y in stride(from: 0.0, through: 900, by: 12) {
                let pointer = CGPoint(x: x, y: y)
                let frame = Loupe.frame(size: size, beside: pointer, in: bounds)
                #expect(bounds.contains(frame))
                #expect(!frame.insetBy(dx: -19.5, dy: -19.5).contains(pointer))
            }
        }
    }

    @Test func staysOnTheDisplayUnderThePointerUntilADragChoosesTheOriginDisplay() throws {
        var session = DisplaySelectionSession(displays: [retina, external], pointer: CGPoint(x: 40, y: 40))
        #expect(session.loupeTarget(at: CGPoint(x: 40, y: 40))?.display == retina)
        #expect(session.loupeTarget(at: CGPoint(x: -100, y: 40))?.display == external)
        #expect(session.loupeTarget(at: CGPoint(x: 5000, y: 40)) == nil)

        session.begin(at: CGPoint(x: -100, y: 40))
        // Dragged onto the other display: the Loupe stays on the Origin display, at its edge.
        let dragged = try #require(session.loupeTarget(at: CGPoint(x: 300, y: 2000)))
        #expect(dragged.display == external)
        #expect(dragged.pointer == CGPoint(x: -1, y: 900))
        let below = try #require(session.loupeTarget(at: CGPoint(x: -3000, y: -900)))
        #expect(below.pointer == CGPoint(x: -1920, y: -179))

        session.updateDisplays([retina])
        #expect(session.loupeTarget(at: CGPoint(x: 40, y: 40)) == nil)
    }
}
