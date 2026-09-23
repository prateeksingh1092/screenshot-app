import CoreGraphics
import Foundation
import FrisketCore
import ImageIO
import Testing

private actor IdleFrames: ScrollingFrameFeed {
    private(set) var served = 0
    func nextFrame() async -> ScrollingFrameEvent {
        served += 1
        return .cancel
    }
}

@Suite struct ScrollingCaptureCommandsTests {
    @Test func scrollingCaptureIsRefusedWhenThePendingByteBudgetIsExceeded() async {
        let frames = IdleFrames()
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(),
            source: OccupyingPixels(), clipboard: IgnoringClipboard(), pendingByteLimit: 4,
            scrollingFrames: frames)
        let occupying = CaptureID()
        #expect(await commands.execute(.capture(occupying, maximumBytes: 4)) == .pending(CaptureRevision(captureID: occupying, number: 1)))
        let scrolling = CaptureID()
        #expect(await commands.execute(.captureScrolling(scrolling, maximumBytes: 4)) == .rejected(.pendingByteBudgetExceeded))
        #expect(await frames.served == 0)
        #expect(await commands.execute(.discard(occupying)) == .discarded(occupying))
        #expect(await commands.execute(.captureScrolling(scrolling, maximumBytes: 4)) == .captureFailed(.cancelled))
        #expect(await frames.served == 1)
    }
}

private struct OccupyingPixels: CapturePixelSource {
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .success(CaptureImage(pngData: Data([9, 8, 7, 6])))
    }
}

private struct IgnoringClipboard: ImageClipboard {
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        .success(ClipboardReceipt(changeCount: 1))
    }
}

extension ScrollingCaptureCommandsTests {
    @Test func v1BudgetMatchesTheStitcherTrialMeasurement() {
        // Ticket 34 completed 5,120 × 57,600 at a 1,270,796,288 byte peak, under ticket 05's 2,000,000,000 byte gate.
        #expect(ScrollingCaptureBudget.v1.pixelCap == 294_912_000)
        #expect(ScrollingCaptureBudget.v1.memoryBudgetBytes == 2_000_000_000)
    }

    @Test func doneScrollingCaptureBecomesAPendingImageAndLivePreview() async throws {
        let frames = ScriptedFrames(try manualFrames(offsets: [0, 80, 160]) + [.done])
        let commands = layer(frames: frames, budget: .v1, pendingByteLimit: 2_000_000)
        let id = CaptureID()
        guard case let .pending(revision) = await commands.execute(.captureScrolling(id, maximumBytes: 2_000_000)) else {
            Issue.record("Expected a pending scrolling capture")
            return
        }
        let stored = try #require(await commands.image(for: revision)?.pngData)
        let image = try decoded(stored)
        let reference = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 560, logicalYOffset: 0))
        #expect(image.width == 240)
        #expect(image.height == 560)
        #expect(image.dataProvider?.data as Data? == reference.dataProvider?.data as Data?)
        let previews = await frames.previews
        #expect(previews.count >= 1)
        #expect(previews.last?.width == 240)
        #expect(previews.last?.height == 560)
        #expect(previews.allSatisfy { !$0.pngData.isEmpty })
    }

    @Test func copyDeliversTheScrollingCapture() async throws {
        let clipboard = RecordingScrollingClipboard()
        let frames = ScriptedFrames(try manualFrames(offsets: [0, 80, 160]) + [.done])
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: OccupyingPixels(),
            clipboard: clipboard, pendingByteLimit: 2_000_000, scrollingFrames: frames, scrollingPreview: frames)
        let id = CaptureID()
        guard case let .pending(revision) = await commands.execute(.captureScrolling(id, maximumBytes: 2_000_000)) else {
            Issue.record("Expected a pending scrolling capture")
            return
        }
        let stored = try #require(await commands.image(for: revision)?.pngData)
        let result = await commands.execute(.copy(revision))
        #expect(result == .copy(CopyOutcome(revision: revision, commit: .notCommitted(.historyUnavailable),
            delivery: .copied(ClipboardReceipt(changeCount: 41)))))
        let delivered = await clipboard.images
        #expect(delivered.map(\.pngData) == [stored])
        #expect(delivered.first?.currentHostOnly == true)
        #expect(delivered.first?.concealed == true)
        #expect(await commands.image(for: revision) == nil)
    }

    @Test func dismissKeepsTheScrollingCaptureInHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("fixture.bundle/History.noindex")
        let frames = ScriptedFrames(try manualFrames(offsets: [0, 80, 160]) + [.done])
        let commands = CaptureCommandLayer(permission: GrantedTestPermission(), source: OccupyingPixels(),
            clipboard: IgnoringClipboard(), pendingByteLimit: 2_000_000, history: HistoryStore(root: root),
            scrollingFrames: frames, scrollingPreview: frames)
        let id = CaptureID()
        guard case let .pending(revision) = await commands.execute(.captureScrolling(id, maximumBytes: 2_000_000)) else {
            Issue.record("Expected a pending scrolling capture")
            return
        }
        let stored = try #require(await commands.image(for: revision)?.pngData)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(await commands.execute(.dismiss(revision)) == .finalized(revision, .committed))
        let entries = try await commands.historyEntries().get()
        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(entry.captureID == id)
        #expect(entry.width == 240 && entry.height == 560)
        #expect(try Data(contentsOf: root.appendingPathComponent(entry.imageLocation)) == stored)
        #expect(await commands.image(for: revision) == nil)
    }

    @Test func pixelCapStopsScrollingWithTheSectionThatFit() async throws {
        let frames = ScriptedFrames(try manualFrames(offsets: [0, 80, 160]) + [.done])
        let budget = ScrollingCaptureBudget(pixelCap: 120_000, memoryBudgetBytes: 50_000_000)
        let commands = layer(frames: frames, budget: budget, pendingByteLimit: 5_000_000)
        guard case let .scrollingLimited(revision, notice) = await commands.execute(.captureScrolling(CaptureID(), maximumBytes: 5_000_000)) else {
            Issue.record("Expected the pixel cap to stop the capture")
            return
        }
        #expect(notice == .pixelCap)
        #expect(notice.message == "Scrolling capture stopped at the pixel limit. The image includes only the section that fit.")
        let image = try decoded(try #require(await commands.image(for: revision)?.pngData))
        #expect(image.width == 240)
        #expect(image.height == 500)
        let previews = await frames.previews
        #expect(previews.last?.notice == .pixelCap)
    }

    @Test func memoryBudgetStopsScrollingWithTheSectionThatFit() async throws {
        let frames = ScriptedFrames(try manualFrames(offsets: [0, 80]) + [.done])
        let budget = ScrollingCaptureBudget(pixelCap: 294_912_000, memoryBudgetBytes: 240 * 400 * 4 * 2)
        let commands = layer(frames: frames, budget: budget, pendingByteLimit: 5_000_000)
        guard case let .scrollingLimited(revision, notice) = await commands.execute(.captureScrolling(CaptureID(), maximumBytes: 5_000_000)) else {
            Issue.record("Expected the memory budget to stop the capture")
            return
        }
        #expect(notice == .memoryBudget)
        #expect(notice.message == "Scrolling capture stopped at the memory limit. The image includes only the section that fit.")
        let image = try decoded(try #require(await commands.image(for: revision)?.pngData))
        #expect(image.width == 240)
        #expect(image.height == 400)
    }

    @Test func ingestReleasesTheViewportImage() throws {
        let session = ScrollingCaptureSession(budget: .v1)
        weak var viewportImage: CGImage?
        try autoreleasepool {
            let image = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 400, logicalYOffset: 0))
            viewportImage = image
            _ = session.ingest(try #require(ScrollingViewport(cgImage: image)))
        }
        #expect(viewportImage == nil)
        let finished = try #require(session.finish()?.pngData)
        #expect(try decoded(finished).height == 400)
    }

    private func layer(frames: ScriptedFrames, budget: ScrollingCaptureBudget, pendingByteLimit: Int) -> CaptureCommandLayer {
        CaptureCommandLayer(permission: GrantedTestPermission(), source: OccupyingPixels(), clipboard: IgnoringClipboard(),
            pendingByteLimit: pendingByteLimit, scrollingFrames: frames, scrollingPreview: frames, scrollingBudget: budget)
    }
}

private func manualFrames(offsets: [Int]) throws -> [ScrollingFrameEvent] {
    try offsets.map { offset in
        let image = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 400, logicalYOffset: offset))
        return .viewport(try #require(ScrollingViewport(cgImage: image)))
    }
}

private func decoded(_ data: Data) throws -> CGImage {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
}

private actor ScriptedFrames: ScrollingFrameFeed, ScrollingPreviewSurface {
    private var events: [ScrollingFrameEvent]
    private(set) var previews: [ScrollingPreview] = []
    init(_ events: [ScrollingFrameEvent]) { self.events = events }
    func nextFrame() async -> ScrollingFrameEvent {
        guard !events.isEmpty else { return .done }
        return events.removeFirst()
    }
    func update(_ preview: ScrollingPreview) { previews.append(preview) }
}

private actor RecordingScrollingClipboard: ImageClipboard {
    private(set) var images: [ClipboardImage] = []
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> {
        images.append(image)
        return .success(ClipboardReceipt(changeCount: 41))
    }
}
