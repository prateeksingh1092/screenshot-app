import Foundation
import FrisketCore
import Testing

@Suite struct DisplaySelectionSessionTests {
    private let retina = SelectionDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    private let external = SelectionDisplay(id: 2, frame: CGRect(x: -1920, y: -180, width: 1920, height: 1080), scale: 1)

    @Test func pointsBelongToOneDisplayIncludingNegativeCoordinatesAndSharedEdges() {
        let session = DisplaySelectionSession(displays: [retina, external], pointer: CGPoint(x: 40, y: 40))
        #expect(session.display(at: CGPoint(x: -100, y: -100)) == external)
        #expect(session.display(at: CGPoint(x: 0, y: 0)) == retina)
        #expect(session.display(at: CGPoint(x: -1920, y: -180)) == external)
        #expect(session.display(at: CGPoint(x: 1440, y: 200)) == nil)
        #expect(session.display(at: CGPoint(x: 10, y: -100)) == nil)
        #expect(session.originDisplay == retina)
        #expect(session.rect == CGRect(x: 560, y: 360, width: 320, height: 180))
    }

    @Test func dragChoosesItsDisplayAndCannotTransferAcrossTheEdge() {
        var session = DisplaySelectionSession(displays: [retina, external], pointer: CGPoint(x: 40, y: 40))
        let began = session.begin(at: CGPoint(x: -100, y: -100))
        #expect(began)
        session.update(to: CGPoint(x: 100, y: 100))
        #expect(session.originDisplay == external)
        #expect(session.rect == CGRect(x: -100, y: -100, width: 100, height: 200))
        let transferred = session.begin(at: CGPoint(x: 100, y: 100))
        #expect(!transferred)
        session.nudge(dx: -1, dy: 1)
        session.resize(dw: -1, dh: 1)
        #expect(session.rect == CGRect(x: -101, y: -99, width: 99, height: 201))
        #expect(session.originDisplay == external)
    }

    @Test(arguments: ["origin removed", "other removed", "moved", "scaled", "added", "all removed"])
    func layoutChangesCancelWithoutAllowingTheOldSelectionToResume(change: String) {
        var session = DisplaySelectionSession(displays: [retina, external], pointer: CGPoint(x: 40, y: 40))
        session.begin(at: CGPoint(x: -100, y: -100))
        session.update(to: CGPoint(x: -20, y: 100))
        session.updateDisplays([external, retina])
        #expect(!session.isCancelled)
        #expect(session.rect == CGRect(x: -100, y: -100, width: 80, height: 200))
        let changed: [SelectionDisplay]
        switch change {
        case "origin removed": changed = [retina]
        case "other removed": changed = [external]
        case "moved": changed = [retina, SelectionDisplay(id: 2, frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), scale: 1)]
        case "scaled": changed = [SelectionDisplay(id: 1, frame: retina.frame, scale: 1), external]
        case "added": changed = [retina, external, SelectionDisplay(id: 3, frame: CGRect(x: 1440, y: 0, width: 800, height: 600), scale: 1)]
        default: changed = []
        }
        session.updateDisplays(changed)
        #expect(session.isCancelled)
        #expect(session.rect == nil)
        #expect(session.originDisplay == nil)
        session.updateDisplays([retina, external])
        let restarted = session.begin(at: CGPoint(x: 40, y: 40))
        #expect(!restarted)
        session.nudge(dx: 1, dy: 1)
        session.resize(dw: 1, dh: 1)
        session.update(to: CGPoint(x: 100, y: 100))
        #expect(session.rect == nil)
    }
}

extension DisplaySelectionSessionTests {
    /// D14: with the pointer on a display's top pixel row, AppKit reports y == frame.maxY, which the
    /// half-open lookup gives to no display, so no Selection can start (story 86).
    @Test func d14PointerOnATopPixelRowHasAnOriginDisplay() async throws {
        try await knownDefect("D14") {
            for (pointer, owner) in [(CGPoint(x: 720, y: 900), retina), (CGPoint(x: 0, y: 900), retina),
                                     (CGPoint(x: -960, y: 900), external), (CGPoint(x: -1920, y: 900), external)] {
                var session = DisplaySelectionSession(displays: [retina, external], pointer: pointer)
                #expect(session.originDisplay == owner, "D14: no Origin display for a pointer at \(pointer)")
                let began = session.begin(at: pointer)
                #expect(began, "D14: a Selection cannot start at \(pointer)")
            }
        }
    }

    /// A pointer on a display's minimum x already has an Origin display; the D14 fix must keep it.
    @Test func pointerOnALeftmostPixelColumnHasAnOriginDisplay() {
        let session = DisplaySelectionSession(displays: [retina, external], pointer: CGPoint(x: -1920, y: 400))
        #expect(session.originDisplay == external)
        #expect(session.display(at: CGPoint(x: 0, y: 400)) == retina)
    }
}
