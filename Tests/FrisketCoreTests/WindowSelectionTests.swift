import CoreGraphics
import FrisketCore
import Testing

/// Window capture picks the window under the pointer, never system chrome (D2, story 84).
/// ScreenCaptureKit lists the cursor itself as a window: an empty owning-app bundle ID at
/// layer 2147483630, in front of everything. Frames are global top-left-origin points.
@Suite struct WindowSelectionTests {
    private static let ownBundle = "io.github.prateeksingh1092.frisket.debug"
    private static let pointer = CGPoint(x: 500, y: 300)
    /// The synthetic pattern window the user meant to capture.
    private static let pattern = WindowCandidate(id: 10, ownerProcessID: 501, bundleIdentifier: "fixture.pattern",
        frame: CGRect(x: 100, y: 100, width: 800, height: 600), layer: 0, isOnScreen: true, isMinimized: false)

    /// Each intruder sits in front of the pattern window, under the pointer, and isolates one rejection rule.
    private static func intruder(_ kind: String) -> WindowCandidate {
        func window(_ bundle: String, _ frame: CGRect, layer: Int) -> WindowCandidate {
            WindowCandidate(id: 4, ownerProcessID: 380, bundleIdentifier: bundle, frame: frame,
                            layer: layer, isOnScreen: true, isMinimized: false)
        }
        let around = CGRect(x: 300, y: 200, width: 400, height: 300)
        switch kind {
        case "cursor": // As listed live: empty bundle ID, cursor level, pointer-sized.
            return window("", CGRect(x: 496, y: 296, width: 20, height: 26), layer: 2_147_483_630)
        case "empty bundle ID":
            return window("", around, layer: 0)
        case "pop-up menu level":
            return window("fixture.menu", around, layer: 101)
        case "Dock":
            return window("com.apple.dock", CGRect(x: 0, y: 250, width: 1440, height: 100), layer: 20)
        default: // A helper window smaller than 32 pt on a side.
            return window("fixture.helper", CGRect(x: 492, y: 292, width: 16, height: 16), layer: 0)
        }
    }

    @Test(arguments: ["cursor", "empty bundle ID", "pop-up menu level", "Dock", "tiny helper"])
    func d2WindowUnderThePointerIsPickedNotSystemChrome(_ kind: String) async throws {
        try await knownDefect("D2") {
            let selection = WindowSelection(windows: [Self.intruder(kind), Self.pattern], ownProcessID: 42,
                                            ownBundleIdentifier: Self.ownBundle)
            let picked = selection.window(at: Self.pointer)
            #expect(picked?.id == Self.pattern.id, "D2: the \(kind) window was picked instead of the window under the pointer")
        }
    }

    /// The deliberate floating-window support stays (plan O2): a foreign utility panel is a real target.
    @Test func foreignFloatingWindowInFrontIsStillPicked() {
        let floating = WindowCandidate(id: 80, ownerProcessID: 777, bundleIdentifier: "fixture.floating",
            frame: CGRect(x: 300, y: 200, width: 400, height: 300), layer: 3, isOnScreen: true, isMinimized: false)
        let selection = WindowSelection(windows: [floating, Self.pattern], ownProcessID: 42,
                                        ownBundleIdentifier: Self.ownBundle)
        #expect(selection.window(at: Self.pointer)?.id == floating.id)
    }
}
