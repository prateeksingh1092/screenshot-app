import AppKit
import FrisketCore
@testable import FrisketAdapters
import Testing

/// D26: the Loupe's pixels come through the Selection's own capture route, only once the
/// overlay can be excluded, and at most one small capture is in flight however fast the
/// pointer moves.
@MainActor private final class LoupeScreenAccess: ScreenRecordingAccess {
    var hasRequested = true
    func preflight() -> Bool { true }
    func request() -> Bool { Issue.record("Must not request permission"); return false }
}

@MainActor private final class LoupeDesktop {
    var loads = 0
    var listsFrisket = true
    var requests: [(request: AreaCaptureRequest, excluded: Set<String>)] = []

    func snapshot() -> any ScreenCaptureContent {
        loads += 1
        return Snapshot(desktop: self, listsFrisket: listsFrisket)
    }

    private struct Snapshot: ScreenCaptureContent {
        let desktop: LoupeDesktop
        let listsFrisket: Bool

        func listsOwnProcess(bundleIdentifier: String) -> Bool { listsFrisket && bundleIdentifier == "test.frisket" }

        func captureImage(_ request: AreaCaptureRequest, additionalExclusions: Set<String>) async throws -> CGImage {
            desktop.requests.append((request, request.excludedBundleIdentifiers.union(additionalExclusions)))
            let context = try #require(CGContext(data: nil, width: request.pixelWidth, height: request.pixelHeight,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try #require(context.makeImage())
        }
    }
}

/// A capture that waits until the test releases it, to hold one sample in flight.
@MainActor private final class HeldCapture {
    var started: [LoupeSample] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func capture(_ sample: LoupeSample) async throws -> CGImage {
        started.append(sample)
        await withCheckedContinuation { waiting.append($0) }
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try #require(context.makeImage())
    }

    func releaseOne() async {
        while waiting.isEmpty { await Task.yield() }
        waiting.removeFirst().resume()
        for _ in 0..<20 { await Task.yield() }
    }
}

@Suite @MainActor struct LoupeSamplingTests {
    private let display = SelectionDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)

    private func platform(_ desktop: LoupeDesktop, notifications: NotificationCenter = NotificationCenter()) -> ScreenCapturePlatform {
        ScreenCapturePlatform(permission: ScreenCapturePermissionAdapter(access: LoupeScreenAccess()),
            bundleIdentifier: "test.frisket", exclusions: { ["test.vault"] },
            loadContent: { desktop.snapshot() }, connectedDisplays: { [display] },
            applicationNotifications: notifications)
    }

    private func sample(_ x: CGFloat) throws -> LoupeSample {
        try #require(Loupe.sample(at: CGPoint(x: x, y: 800), on: display))
    }

    @Test func samplesOneSmallSquareThroughTheSelectionsFilter() async throws {
        let desktop = LoupeDesktop()
        let platform = platform(desktop)
        defer { platform.finishCapture() }
        try await platform.prefetchShareableContent()
        let square = try sample(100)
        let image = try await platform.sampleLoupe(square)
        #expect(image.width == 15 && image.height == 15)
        let recorded = try #require(desktop.requests.first)
        #expect(recorded.request.displayID == 1)
        #expect(recorded.request.sourceRect == CGRect(x: 96.5, y: 96.5, width: 7.5, height: 7.5))
        #expect(recorded.request.pixelWidth == 15 && recorded.request.pixelHeight == 15)
        #expect(recorded.excluded == ["test.frisket", "test.vault"])
        // The prefetched snapshot predates the overlay; the Loupe loads its own once.
        _ = try await platform.sampleLoupe(try sample(200))
        #expect(desktop.loads == 2)
    }

    @Test func failsClosedWhenTheSnapshotCannotExcludeTheOverlay() async throws {
        let desktop = LoupeDesktop()
        desktop.listsFrisket = false
        let platform = platform(desktop)
        defer { platform.finishCapture() }
        try await platform.prefetchShareableContent()
        await #expect(throws: (any Error).self) { try await platform.sampleLoupe(try sample(100)) }
        #expect(desktop.requests.isEmpty)
    }

    @Test func anApplicationLaunchRefreshesTheLoupesExclusions() async throws {
        let desktop = LoupeDesktop()
        let notifications = NotificationCenter()
        let platform = platform(desktop, notifications: notifications)
        defer { platform.finishCapture() }
        try await platform.prefetchShareableContent()
        _ = try await platform.sampleLoupe(try sample(100))
        notifications.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        _ = try await platform.sampleLoupe(try sample(200))
        #expect(desktop.loads == 3)
    }

    @Test func noSamplingOutsideACapture() async throws {
        let desktop = LoupeDesktop()
        let platform = platform(desktop)
        await #expect(throws: (any Error).self) { try await platform.sampleLoupe(try sample(100)) }
        #expect(desktop.loads == 0)
    }

    @Test func pointerMovesDuringACaptureCollapseIntoTheLatest() async throws {
        let held = HeldCapture()
        var delivered: [LoupeSample] = []
        let feed = LoupeFeed(capture: { try await held.capture($0) }) { sample, _ in delivered.append(sample) }
        let first = try sample(100)
        feed.request(first)
        for x in stride(from: 101.0, through: 140, by: 1) { feed.request(try sample(x)) }
        feed.request(try sample(140))
        await held.releaseOne()
        await held.releaseOne()
        #expect(held.started == [first, try sample(140)])
        #expect(delivered == [first, try sample(140)])
        // The same square again, with nothing pending, captures nothing.
        feed.request(try sample(140))
        for _ in 0..<20 { await Task.yield() }
        #expect(held.started.count == 2)
    }

    @Test func stoppingDropsTheSampleInFlight() async throws {
        let held = HeldCapture()
        var delivered: [LoupeSample] = []
        let feed = LoupeFeed(capture: { try await held.capture($0) }) { sample, _ in delivered.append(sample) }
        feed.request(try sample(100))
        feed.request(try sample(120))
        feed.stop()
        await held.releaseOne()
        feed.request(try sample(130))
        for _ in 0..<20 { await Task.yield() }
        #expect(held.started == [try sample(100)])
        #expect(delivered.isEmpty)
    }
}
