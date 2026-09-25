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
        case "cursor-level window": // Excluded by layer alone, whatever its bundle ID or size.
            return window("fixture.bundled", around, layer: 2_147_483_630)
        case "pop-up menu level":
            return window("fixture.menu", around, layer: 101)
        case "Dock":
            return window("com.apple.dock", CGRect(x: 0, y: 250, width: 1440, height: 100), layer: 20)
        default: // A helper window smaller than 32 pt on a side.
            return window("fixture.helper", CGRect(x: 492, y: 292, width: 16, height: 16), layer: 0)
        }
    }

    @Test(arguments: ["cursor", "cursor-level window", "pop-up menu level", "Dock", "tiny helper"])
    func d2WindowUnderThePointerIsPickedNotSystemChrome(_ kind: String) {
        let selection = WindowSelection(windows: [Self.intruder(kind), Self.pattern], ownProcessID: 42,
                                        ownBundleIdentifier: Self.ownBundle)
        let picked = selection.window(at: Self.pointer)
        #expect(picked?.id == Self.pattern.id, "D2: the \(kind) window was picked instead of the window under the pointer")
    }

    /// The deliberate floating-window support stays (plan O2): a foreign utility panel is a real target.
    @Test func foreignFloatingWindowInFrontIsStillPicked() {
        let floating = WindowCandidate(id: 80, ownerProcessID: 777, bundleIdentifier: "fixture.floating",
            frame: CGRect(x: 300, y: 200, width: 400, height: 300), layer: 3, isOnScreen: true, isMinimized: false)
        let selection = WindowSelection(windows: [floating, Self.pattern], ownProcessID: 42,
                                        ownBundleIdentifier: Self.ownBundle)
        #expect(selection.window(at: Self.pointer)?.id == floating.id)
    }

    /// Story 84: every window failure message names its own cause, not the area-capture advice.
    @Test func everyWindowFailureMessageNamesItsCause() {
        let messages = WindowCaptureFailure.allCases.map(\.message)
        #expect(Set(messages).count == WindowCaptureFailure.allCases.count)
        for failure in WindowCaptureFailure.allCases {
            #expect(!failure.title.isEmpty && !failure.message.isEmpty)
            #expect(!failure.message.contains("smaller area"), "\(failure) reuses the area-capture advice")
            #expect(failure.message.contains("window"), "\(failure) does not say it is about the window")
        }
    }

    /// Ticket 89: an app without a bundle ID (an unbundled executable, some Java or Python apps) owns
    /// normal windows. ScreenCaptureKit lists its owner with an empty bundle ID, like the cursor.
    @Test func unbundledAppsWindowIsPicked() {
        let unbundled = WindowCandidate(id: 12, ownerProcessID: 9001, bundleIdentifier: "",
            frame: CGRect(x: 300, y: 200, width: 400, height: 300), layer: 0, isOnScreen: true, isMinimized: false)
        let selection = WindowSelection(windows: [unbundled, Self.pattern], ownProcessID: 42,
                                        ownBundleIdentifier: Self.ownBundle)
        #expect(selection.window(at: Self.pointer)?.id == unbundled.id,
                "Ticket 89: a window whose app has no bundle ID was not offered")
    }

    /// Each rejection rule's boundary: the last accepted level and size stay capturable.
    @Test func windowsJustInsideTheRulesArePicked() {
        let utility = WindowCandidate(id: 11, ownerProcessID: 501, bundleIdentifier: "fixture.utility",
            frame: CGRect(x: 484, y: 284, width: 32, height: 32), layer: 19, isOnScreen: true, isMinimized: false)
        let selection = WindowSelection(windows: [utility, Self.pattern], ownProcessID: 42,
                                        ownBundleIdentifier: Self.ownBundle)
        #expect(selection.window(at: Self.pointer)?.id == utility.id)
    }
}

/// `WindowSelection(rows:)` owns the join of the window list with ScreenCaptureKit's shareable
/// windows, and the filter (ticket 75). Rows are shaped like the live listings behind D2.
@Suite struct WindowSelectionRowsTests {
    private static let ownBundle = "io.github.prateeksingh1092.frisket.debug"
    private static let pointer = CGPoint(x: 500, y: 300)
    private static let frame = CGRect(x: 100, y: 100, width: 800, height: 600)

    private static func listed(_ id: UInt32, pid: Int32, layer: Int? = 0, onScreen: Bool = true) -> WindowListRow {
        WindowListRow(id: id, ownerProcessID: pid, layer: layer, isOnScreen: onScreen)
    }
    private static func shareable(_ id: UInt32, pid: Int32?, bundle: String?, frame: CGRect = frame,
                                  layer: Int = 0, onScreen: Bool = true) -> ShareableWindowRow {
        ShareableWindowRow(id: id, ownerProcessID: pid, bundleIdentifier: bundle, frame: frame,
                           layer: layer, isOnScreen: onScreen)
    }
    private static func selection(_ rows: WindowRows, excluding: Set<String> = []) -> WindowSelection {
        WindowSelection(rows: rows, excluding: excluding, ownProcessID: 42, ownBundleIdentifier: ownBundle)
    }
    private static let pattern = (listed(10, pid: 501), shareable(10, pid: 501, bundle: "fixture.pattern"))

    @Test func d2CursorListedByBothSourcesIsNeverPicked() {
        // Live listing: the cursor (id 4) is front-most in both the window list and ScreenCaptureKit.
        let rows = WindowRows(
            ordered: [Self.listed(4, pid: 380, layer: 2_147_483_630), Self.pattern.0],
            shareable: [Self.shareable(4, pid: 380, bundle: "", frame: CGRect(x: 496, y: 296, width: 20, height: 26),
                                       layer: 2_147_483_630), Self.pattern.1])
        #expect(Self.selection(rows).window(at: Self.pointer)?.id == 10)
        #expect(Self.selection(rows).candidates.map(\.id) == [10])
    }

    /// Ticket 89, as listed live by `sckwins 5000`: the synthetic pattern window, run as an unbundled
    /// executable, is `owner=pattern bundle=""` at layer 0, behind the cursor under the pointer.
    @Test func unbundledAppsWindowIsOfferedAndTheCursorIsNot() {
        let rows = WindowRows(
            ordered: [Self.listed(4, pid: 380, layer: 2_147_483_630), Self.listed(10, pid: 501)],
            shareable: [Self.shareable(4, pid: 380, bundle: "", frame: CGRect(x: 496, y: 296, width: 20, height: 26),
                                       layer: 2_147_483_630),
                        Self.shareable(10, pid: 501, bundle: "")])
        let selection = Self.selection(rows, excluding: ["test.synthetic-vault"])
        #expect(selection.candidates.map(\.id) == [10], "Ticket 89: the unbundled pattern window was not offered")
        #expect(selection.window(at: Self.pointer)?.id == 10)
    }

    @Test func orderComesFromTheWindowListNotScreenCaptureKit() {
        let front = (Self.listed(20, pid: 600), Self.shareable(20, pid: 600, bundle: "fixture.front"))
        let rows = WindowRows(ordered: [front.0, Self.pattern.0], shareable: [Self.pattern.1, front.1])
        #expect(Self.selection(rows).candidates.map(\.id) == [20, 10])
    }

    @Test(arguments: ["not shareable", "no owning app", "owner changed", "layer changed", "no layer",
                      "off screen in the window list", "off screen in ScreenCaptureKit", "on the exclusion list"])
    func joinDropsWindowsThatDoNotMatch(_ kind: String) {
        let front: (WindowListRow, ShareableWindowRow?) = switch kind {
        case "not shareable": (Self.listed(20, pid: 600), nil)
        case "no owning app": (Self.listed(20, pid: 600), Self.shareable(20, pid: nil, bundle: nil))
        case "owner changed": (Self.listed(20, pid: 600), Self.shareable(20, pid: 601, bundle: "fixture.front"))
        case "layer changed": (Self.listed(20, pid: 600, layer: 3), Self.shareable(20, pid: 600, bundle: "fixture.front"))
        case "no layer": (Self.listed(20, pid: 600, layer: nil), Self.shareable(20, pid: 600, bundle: "fixture.front"))
        case "off screen in the window list":
            (Self.listed(20, pid: 600, onScreen: false), Self.shareable(20, pid: 600, bundle: "fixture.front"))
        case "off screen in ScreenCaptureKit":
            (Self.listed(20, pid: 600), Self.shareable(20, pid: 600, bundle: "fixture.front", onScreen: false))
        default: (Self.listed(20, pid: 600), Self.shareable(20, pid: 600, bundle: "test.synthetic-vault"))
        }
        let rows = WindowRows(ordered: [front.0, Self.pattern.0], shareable: [front.1, Self.pattern.1].compactMap { $0 })
        let selection = Self.selection(rows, excluding: ["test.synthetic-vault"])
        #expect(selection.candidates.map(\.id) == [10], "\(kind): the window joined as a capture target")
        #expect(selection.window(at: Self.pointer)?.id == 10)
    }

    @Test func frisketsOwnWindowsAreNotCandidates() {
        let own = (Self.listed(30, pid: 42, layer: 3), Self.shareable(30, pid: 42, bundle: Self.ownBundle, layer: 3))
        let rows = WindowRows(ordered: [own.0, Self.pattern.0], shareable: [own.1, Self.pattern.1])
        #expect(Self.selection(rows).candidates.map(\.id) == [10])
    }
}
