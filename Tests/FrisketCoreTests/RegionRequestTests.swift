import CoreGraphics
import FrisketCore
import Testing

/// Area and full-screen capture ask ScreenCaptureKit for one `RegionRequest` (ticket 75).
/// Displays: a 1440 × 900 primary at 2× and a 1920 × 1080 display to its left, 180 pt lower, at 1×.
@Suite struct RegionRequestTests {
    private static let primary = SelectionDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    private static let left = SelectionDisplay(id: 2, frame: CGRect(x: -1920, y: -180, width: 1920, height: 1080), scale: 1)
    private static let displays = CaptureDisplays([left, primary])

    @Test func areaIsClippedToItsDisplayFlippedToTopLeftAndSnappedOutwardToPixels() throws {
        let rect = CGRect(x: -900.3, y: -300, width: 300.5, height: 400.2) // Runs off the bottom edge.
        let request = try RegionRequest.area(rect, on: Self.left, decodedByteCeiling: .max).get()
        #expect(request.displayID == 2)
        // Clipped to y -180...100.2; top-left y is 900 - 100.2 = 799.8, floored to 799.
        #expect(request.sourceRect == CGRect(x: 1019, y: 799, width: 302, height: 281))
        #expect(request.pixelWidth == 302 && request.pixelHeight == 281)
    }

    @Test func areaOnARetinaDisplayCountsDevicePixels() throws {
        let request = try RegionRequest.area(CGRect(x: 100, y: 500, width: 300, height: 150), on: Self.primary,
                                             decodedByteCeiling: .max).get()
        #expect(request.sourceRect == CGRect(x: 100, y: 250, width: 300, height: 150))
        #expect(request.pixelWidth == 600 && request.pixelHeight == 300)
    }

    @Test func areaOutsideItsDisplayIsEmptyAndAnOversizedBitmapIsRefused() {
        #expect(RegionRequest.area(CGRect(x: 2000, y: 0, width: 10, height: 10), on: Self.primary,
                                   decodedByteCeiling: .max) == .failure(.emptyImage))
        #expect(RegionRequest.area(CGRect(x: 0, y: 0, width: 10, height: 10), on: Self.primary,
                                   decodedByteCeiling: 20 * 20 * 4 - 1) == .failure(.unavailable))
    }

    @Test func fullScreenIsTheWholeDisplay() throws {
        let request = try RegionRequest.fullScreen(Self.primary, decodedByteCeiling: .max).get()
        #expect(.success(request) == RegionRequest.area(Self.primary.frame, on: Self.primary, decodedByteCeiling: .max))
        #expect(request.sourceRect == CGRect(x: 0, y: 0, width: 1440, height: 900))
        #expect(request.pixelWidth == 2880 && request.pixelHeight == 1800)
    }

    @Test func pointerTopRowBelongsToItsDisplayAndSharedEdgesHaveOneOwner() {
        #expect(Self.displays.display(at: CGPoint(x: 10, y: 900))?.id == 1) // D14: top row.
        #expect(Self.displays.display(at: CGPoint(x: 0, y: 450))?.id == 1)
        #expect(Self.displays.display(at: CGPoint(x: -1, y: 450))?.id == 2)
        #expect(Self.displays.display(at: CGPoint(x: 10, y: 901)) == nil)
    }

    @Test func flipIsItsOwnInverseAgainstThePrimaryTop() {
        let rect = CGRect(x: -800, y: -200, width: 600, height: 400) // Top-left global, above the primary.
        #expect(Self.displays.flipped(rect) == CGRect(x: -800, y: 700, width: 600, height: 400))
        #expect(Self.displays.flipped(Self.displays.flipped(rect)) == rect)
        #expect(Self.displays.flipped(CGPoint(x: 5, y: 0)) == CGPoint(x: 5, y: 900))
    }

    @Test func windowBelongsToTheDisplayHoldingMostOfIt() {
        // Top-left global: 700 pt on the left display, 100 pt on the primary.
        #expect(Self.displays.display(mostOverlapping: CGRect(x: -700, y: 100, width: 800, height: 400))?.id == 2)
        #expect(Self.displays.display(mostOverlapping: CGRect(x: -100, y: 100, width: 800, height: 400))?.id == 1)
        #expect(Self.displays.display(mostOverlapping: CGRect(x: 5000, y: 0, width: 10, height: 10)) == nil)
    }
}
