import Foundation
import FrisketCore
import Testing

@Suite struct SelectionGeometryTests {
    @Test(arguments: [1.0, 2.0]) func defaultKeyboardSelectionIsPixelAligned(scale: Double) {
        var selection = SelectionGeometry(displayFrame: CGRect(x: 0, y: 0, width: 801, height: 601), scale: scale)
        #expect(selection.rect == (scale == 1
            ? CGRect(x: 241, y: 211, width: 320, height: 180)
            : CGRect(x: 240.5, y: 210.5, width: 320, height: 180)))
        selection.nudge(dx: -1, dy: 1)
        #expect(selection.rect == (scale == 1
            ? CGRect(x: 240, y: 212, width: 320, height: 180)
            : CGRect(x: 240, y: 211, width: 320, height: 180)))
    }

    @Test func optionAndSpaceKeepTheClippedSizeWhenSpaceIsReleased() {
        var selection = SelectionGeometry(displayFrame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 1)
        selection.begin(at: CGPoint(x: 100, y: 100))
        selection.update(to: CGPoint(x: 300, y: 200), modifiers: [.option])
        #expect(selection.rect == CGRect(x: 0, y: 0, width: 200, height: 200))
        selection.update(to: CGPoint(x: 300, y: 200), modifiers: [.option, .space])
        selection.update(to: CGPoint(x: 350, y: 250), modifiers: [.option, .space])
        #expect(selection.rect == CGRect(x: 50, y: 50, width: 200, height: 200))
        selection.update(to: CGPoint(x: 350, y: 250), modifiers: [.option])
        #expect(selection.rect == CGRect(x: 50, y: 50, width: 200, height: 200))
        selection.update(to: CGPoint(x: 360, y: 255), modifiers: [.option, .shift])
        #expect(selection.rect == CGRect(x: 40, y: 50, width: 220, height: 200))
    }

    @Test(arguments: [1.0, 2.0]) func arrowsNudgeOneDevicePixelAndKeepTheDragAttached(scale: Double) {
        var selection = SelectionGeometry(displayFrame: CGRect(x: -800, y: -200, width: 800, height: 600), scale: scale)
        selection.begin(at: CGPoint(x: -100, y: 0))
        selection.update(to: CGPoint(x: -50, y: 80))
        selection.nudge(dx: 1, dy: -1)
        #expect(selection.rect == (scale == 1
            ? CGRect(x: -99, y: -1, width: 50, height: 80)
            : CGRect(x: -99.5, y: -0.5, width: 50, height: 80)))
        selection.update(to: CGPoint(x: -40, y: 90))
        #expect(selection.rect == (scale == 1
            ? CGRect(x: -99, y: -1, width: 60, height: 90)
            : CGRect(x: -99.5, y: -0.5, width: 60, height: 90)))
        selection.nudge(dx: 4000, dy: -4000)
        #expect(selection.rect == CGRect(x: -60, y: -200, width: 60, height: 90))
        selection.nudge(dx: -4000, dy: 4000)
        #expect(selection.rect == CGRect(x: -800, y: 310, width: 60, height: 90))
    }

    @Test func spaceMovesWithoutResizingAndReleaseResumesWithoutJump() {
        var selection = SelectionGeometry(displayFrame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 2)
        selection.begin(at: CGPoint(x: 100, y: 100))
        selection.update(to: CGPoint(x: 200, y: 180))
        selection.update(to: CGPoint(x: 200, y: 180), modifiers: [.space])
        selection.update(to: CGPoint(x: 250, y: 230), modifiers: [.space])
        #expect(selection.rect == CGRect(x: 150, y: 150, width: 100, height: 80))
        selection.update(to: CGPoint(x: 250, y: 230))
        #expect(selection.rect == CGRect(x: 150, y: 150, width: 100, height: 80))
        selection.update(to: CGPoint(x: 260, y: 240))
        #expect(selection.rect == CGRect(x: 150, y: 150, width: 110, height: 90))
        selection.update(to: CGPoint(x: 260, y: 240), modifiers: [.space])
        selection.update(to: CGPoint(x: 2000, y: 2000), modifiers: [.space])
        #expect(selection.rect == CGRect(x: 690, y: 510, width: 110, height: 90))
        selection.update(to: CGPoint(x: 2000, y: 2000))
        #expect(selection.rect == CGRect(x: 690, y: 510, width: 110, height: 90))
    }

    @Test(arguments: [true, false]) func shiftLocksTheChosenAxisUntilReleased(horizontal: Bool) {
        var selection = SelectionGeometry(displayFrame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 1)
        selection.begin(at: CGPoint(x: 100, y: 100))
        selection.update(to: CGPoint(x: 200, y: 180))
        selection.update(to: CGPoint(x: 200, y: 180), modifiers: [.shift])
        selection.update(to: horizontal ? CGPoint(x: 250, y: 190) : CGPoint(x: 210, y: 230), modifiers: [.shift])
        #expect(selection.rect == (horizontal
            ? CGRect(x: 100, y: 100, width: 150, height: 80)
            : CGRect(x: 100, y: 100, width: 100, height: 130)))
        selection.update(to: CGPoint(x: 280, y: 350), modifiers: [.shift])
        #expect(selection.rect == (horizontal
            ? CGRect(x: 100, y: 100, width: 180, height: 80)
            : CGRect(x: 100, y: 100, width: 100, height: 250)))
        selection.update(to: CGPoint(x: 280, y: 350))
        #expect(selection.rect == CGRect(x: 100, y: 100, width: 180, height: 250))
    }

    @Test func optionGrowsSymmetricallyAndStopsAtNearestDisplayEdge() {
        var selection = SelectionGeometry(displayFrame: CGRect(x: -800, y: -200, width: 800, height: 600), scale: 2)
        selection.begin(at: CGPoint(x: -100, y: 0))
        selection.update(to: CGPoint(x: -250, y: 250), modifiers: [.option])
        #expect(selection.rect == CGRect(x: -200, y: -200, width: 200, height: 400))
        selection.update(to: CGPoint(x: -250, y: 250))
        #expect(selection.rect == CGRect(x: -250, y: 0, width: 150, height: 250))
    }

    @Test(arguments: [1.0, 2.0]) func roundsEndpointsToDevicePixels(scale: Double) {
        var selection = SelectionGeometry(displayFrame: CGRect(x: -800, y: -200, width: 800, height: 600), scale: scale)
        selection.begin(at: CGPoint(x: -699.74, y: -99.74))
        selection.update(to: CGPoint(x: -650.26, y: -50.26))
        let expected = scale == 1
            ? CGRect(x: -700, y: -100, width: 50, height: 50)
            : CGRect(x: -699.5, y: -99.5, width: 49, height: 49)
        #expect(selection.rect == expected)
    }

    @Test func dragStaysOnOriginDisplayWithNegativeCoordinates() {
        var selection = SelectionGeometry(displayFrame: CGRect(x: -800, y: -200, width: 800, height: 600), scale: 1)
        selection.begin(at: CGPoint(x: -100, y: 100))
        selection.update(to: CGPoint(x: -950, y: 550))
        #expect(selection.rect == CGRect(x: -800, y: 100, width: 700, height: 300))
    }
}
