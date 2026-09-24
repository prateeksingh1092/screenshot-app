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
        #expect(ScrollingCaptureBudget.v1.pixelCap == CaptureBudgets.v1.scrollingPixelCap)
        #expect(ScrollingCaptureBudget.v1.pixelCap == 294_912_000)
        #expect(ScrollingCaptureBudget.v1.memoryBudgetBytes == CaptureBudgets.v1.scrollingMemoryBytes)
        #expect(ScrollingCaptureBudget.v1.memoryBudgetBytes == 2_000_000_000)
        #expect(ScrollingCaptureBudget.v1.encodedByteCeiling == CaptureBudgets.v1.scrollingEncodedBytes)
        let applied = ScrollingCaptureBudget.forCapture(template: .v1, encodedByteCeiling: 128 * 1024 * 1024)
        #expect(applied.memoryBudgetBytes == 2_000_000_000)
        #expect(applied.encodedByteCeiling == 128 * 1024 * 1024)
        #expect(applied.memoryBudgetBytes > applied.encodedByteCeiling)
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

    @Test func rejectedAlignmentCannotBecomeAPendingPrefixOnDone() async throws {
        let unrelated = try #require(TestImageFactory.solidColor(width: 240, height: 400))
        let frames = ScriptedFrames(try manualFrames(offsets: [0]) + [
            .viewport(try #require(ScrollingViewport(cgImage: unrelated))), .done
        ])
        let commands = layer(frames: frames, budget: .v1, pendingByteLimit: 2_000_000)
        let id = CaptureID()
        let result = await commands.execute(.captureScrolling(id, maximumBytes: 2_000_000))
        guard case let .captureFailed(.rejectedAlignment(evidence)) = result else {
            Issue.record("Rejected alignment must fail, got \(result)")
            return
        }
        #expect(evidence.disposition == .rejectedAlignment)
        #expect(evidence.appendedRows == 0)
        #expect(evidence.confidence == 0)
        #expect(await commands.image(for: CaptureRevision(captureID: id, number: 1)) == nil)
        // A failed capture releases its entire reservation.
        #expect(await commands.execute(.capture(CaptureID(), maximumBytes: 2_000_000)) != .rejected(.pendingByteBudgetExceeded))
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

    @Test func encodedCeilingStopsScrollingWithoutReducingTheMemoryBudget() async throws {
        let frames = ScriptedFrames(try manualFrames(offsets: [0, 80]) + [.done])
        let budget = ScrollingCaptureBudget(pixelCap: CaptureBudgets.v1.scrollingPixelCap,
                                             memoryBudgetBytes: CaptureBudgets.v1.scrollingMemoryBytes,
                                             encodedByteCeiling: 240 * 400 * 4 * 2)
        let allowance = 240 * 400 * 4 * 2
        let commands = layer(frames: frames, budget: budget, pendingByteLimit: allowance)
        guard case let .scrollingLimited(revision, notice) = await commands.execute(.captureScrolling(CaptureID(), maximumBytes: allowance)) else {
            Issue.record("Expected the encoded ceiling to stop the capture")
            return
        }
        #expect(notice == .encodedCeiling)
        #expect(notice.message == "Scrolling capture stopped at the size limit. The image includes only the section that fit.")
        let image = try decoded(try #require(await commands.image(for: revision)?.pngData))
        #expect(image.width == 240)
        #expect(image.height == 400)
        #expect(budget.memoryBudgetBytes == 2_000_000_000)
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

extension ScrollingCaptureCommandsTests {
    @Test(arguments: ["area", "fullScreen", "scrolling"])
    func permissionWaitReservesScrollingBudgetAndIdentifier(kind: String) async {
        for duplicate in [false, true] {
            let permission = SuspendedScrollingPermission()
            let commands = CaptureCommandLayer(permission: permission,
                source: OccupyingPixels(), fullScreenSource: OccupyingPixels(),
                clipboard: IgnoringClipboard(), pendingByteLimit: duplicate ? 8 : 4,
                scrollingFrames: IdleFrames())
            let id = CaptureID()
            let first = Task { await commands.execute(.captureScrolling(id, maximumBytes: 4)) }
            await permission.waitUntilRequested()
            let otherID = duplicate ? id : CaptureID()
            let competing: CaptureCommand
            switch kind {
            case "area": competing = .capture(otherID, maximumBytes: 4)
            case "fullScreen": competing = .captureFullScreen(otherID, maximumBytes: 4)
            default: competing = .captureScrolling(otherID, maximumBytes: 4)
            }
            let result = await commands.execute(competing)
            await permission.resolve(.granted)
            #expect(result == .rejected(duplicate ? .commandInProgress : .pendingByteBudgetExceeded))
            #expect(await first.value == .captureFailed(.cancelled))
            #expect(await commands.image(for: CaptureRevision(captureID: otherID, number: 1)) == nil)
            // Both the identifier and all reserved bytes are released on cancellation.
            #expect(await commands.execute(.capture(id, maximumBytes: 4)) == .pending(CaptureRevision(captureID: id, number: 1)))
        }
    }
}

private actor SuspendedScrollingPermission: CapturePermissionSource {
    private var requested = false
    private var waiting: CheckedContinuation<CapturePermissionState, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    func capturePermission() async -> CapturePermissionState {
        if requested { return .granted }
        requested = true
        return await withCheckedContinuation { continuation in
            waiting = continuation
            observer?.resume()
            observer = nil
        }
    }

    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { observer = $0 }
    }

    func resolve(_ state: CapturePermissionState) {
        waiting?.resume(returning: state)
        waiting = nil
    }
}


extension ScrollingCaptureCommandsTests {
    @Test func liveSessionMatchesPureStitcherWithoutWaitingForDone() throws {
        let session = ScrollingCaptureSession(budget: .v1)
        let offsets = [0, 80, 80, 160]
        let images = try offsets.map {
            try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 400, logicalYOffset: $0))
        }
        let pure = try Stitcher.stitch(images.map { ScrollingCaptureFrame(image: $0) })
        #expect(pure.alignments.map(\.disposition) == [.initialFrame, .appended, .noMovement, .appended])
        for (index, image) in images.enumerated() {
            let result = session.ingest(try #require(ScrollingViewport(cgImage: image)))
            if index == 2 {
                #expect(result == .unchanged)
            } else {
                guard case let .preview(preview) = result else {
                    Issue.record("Each moving viewport must produce a preview before Done")
                    return
                }
                #expect(preview.width == 240)
                #expect(preview.height == [400, 480, 480, 560][index])
                #expect(!preview.pngData.isEmpty)
            }
        }
        let finished = try decoded(try #require(session.finish()?.pngData))
        let reference = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 560, logicalYOffset: 0))
        #expect(finished.dataProvider?.data as Data? == pure.image.dataProvider?.data as Data?)
        #expect(finished.dataProvider?.data as Data? == reference.dataProvider?.data as Data?)
    }

    @Test func liveAlignmentRejectionPreservesPureEvidenceAndPreventsFinish() throws {
        let session = ScrollingCaptureSession(budget: .v1)
        let initial = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 400, logicalYOffset: 0))
        let unrelated = try #require(TestImageFactory.solidColor(width: 240, height: 400))
        let pure = try Stitcher.stitch([initial, unrelated].map { ScrollingCaptureFrame(image: $0) })
        _ = session.ingest(try #require(ScrollingViewport(cgImage: initial)))
        guard case let .rejectedAlignment(evidence) = session.ingest(try #require(ScrollingViewport(cgImage: unrelated))) else {
            Issue.record("Expected explicit alignment rejection")
            return
        }
        #expect(evidence == pure.alignments.last)
        #expect(evidence.disposition == .rejectedAlignment)
        #expect(session.finish() == nil)
        #expect(session.ingest(try #require(ScrollingViewport(cgImage: initial))) == .rejectedAlignment(evidence))
    }

    @Test(arguments: [CapturePermissionState.notAsked, .denied, .revokedWhileRunning, .needsRelaunch])
    func refusedPermissionReleasesScrollingReservation(state: CapturePermissionState) async {
        let permission = SuspendedScrollingPermission()
        let frames = IdleFrames()
        let commands = CaptureCommandLayer(permission: permission, source: OccupyingPixels(),
            clipboard: IgnoringClipboard(), pendingByteLimit: 4, scrollingFrames: frames)
        let id = CaptureID()
        let capture = Task { await commands.execute(.captureScrolling(id, maximumBytes: 4)) }
        await permission.waitUntilRequested()
        await permission.resolve(state)
        #expect(await capture.value == .permissionRequired(state))
        #expect(await frames.served == 0)
        #expect(await commands.execute(.capture(id, maximumBytes: 4)) == .pending(CaptureRevision(captureID: id, number: 1)))
    }
}


extension ScrollingCaptureCommandsTests {
    @Test func ambiguousWideViewportCannotFinishAsPartialCapture() throws {
        let session = ScrollingCaptureSession(budget: .v1)
        let first = try #require(TestImageFactory.repeatedScrollingFrame(width: 1920, height: 1080, logicalYOffset: 0))
        let second = try #require(TestImageFactory.repeatedScrollingFrame(width: 1920, height: 1080, logicalYOffset: 360))
        _ = session.ingest(try #require(ScrollingViewport(cgImage: first)))
        // The original memory fixture ignored this rejection. A conservative
        // matcher may reject ambiguity; a pixel matcher may accept all 360 rows
        // (1440). Vision on this Intel host can also accept a nearby period
        // (observed 1488). The forbidden outcome is an unchanged 1080 prefix.
        switch session.ingest(try #require(ScrollingViewport(cgImage: second))) {
        case .rejectedAlignment:
            #expect(session.finish() == nil)
        case let .preview(preview):
            #expect(preview.height > 1080)
            #expect(try decoded(try #require(session.finish()?.pngData)).height == preview.height)
        default:
            Issue.record("A moved viewport must never silently become an unchanged prefix")
        }
    }
}
