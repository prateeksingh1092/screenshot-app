import CoreGraphics
import Foundation
import ImageIO
import Testing
import FrisketCore

// Round trips through the production seam, `ScrollingCaptureSession.ingest` (spec, remediation
// seams): a synthetic page is cut into viewports the way a manual scroll samples it, every
// viewport is ingested, and the finished image must be the page again. Ported from the D3
// loops on branch `diagnose/red-loops` (commit 4869429) without their debug probes.

/// A tall synthetic page, top row first, like the live harness's `--show-scroll` page: a uniform
/// dark background with a 320×180 four-colour block every `period` rows, and a black 8×8 marker
/// in each block. With `uniqueMarkers`, the marker moves right in each block, so no two blocks
/// are the same; without, the page repeats exactly every `period` rows below `blockStart`.
/// With `texturedBlocks`, each row of a block has its own shade, as text lines differ; without,
/// each block half is 90 identical rows, like the live page.
struct SyntheticScrollPage {
    let width: Int
    let height: Int
    let bytes: Data
    /// One value per row; equal rows have equal values. The ambiguity oracle compares these.
    let rowIDs: [Int]
    /// Rows that are not one flat colour. Only these are evidence for a scroll step.
    let informativeRows: [Bool]

    init(width: Int = 700, height: Int = 2_400, blockStart: Int = 145, period: Int = 400,
         uniqueMarkers: Bool = false, texturedBlocks: Bool = false) {
        precondition(width >= 336 && period > 180)
        self.width = width
        self.height = height
        var bytes = Data(count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let pixels = raw.bindMemory(to: UInt32.self)
            let blockX = (width - 320) / 2
            for y in 0..<height {
                let block = (y - blockStart) / period
                let localY = (y - blockStart) % period
                let inBlock = y >= blockStart && localY < 180
                let markerX = 8 + (uniqueMarkers ? (block % 16) * 9 : 0)
                for x in 0..<width {
                    var rgb: (UInt32, UInt32, UInt32) = (43, 43, 43)
                    let localX = x - blockX
                    if inBlock, localX >= 0, localX < 320 {
                        if localY >= 164, localY < 172, localX >= markerX, localX < markerX + 8 {
                            rgb = (0, 0, 0)
                        } else {
                            let shade = texturedBlocks ? UInt32(localY) : 0
                            switch (localY < 90, localX < 160) {
                            case (true, true): rgb = (255, shade, 0)
                            case (true, false): rgb = (shade, 255, 0)
                            case (false, true): rgb = (0, shade, 255)
                            case (false, false): rgb = (255, 255, 255 - shade)
                            }
                        }
                    }
                    pixels[y * width + x] = rgb.0 | rgb.1 << 8 | rgb.2 << 16 | 255 << 24
                }
            }
        }
        self.bytes = bytes
        // Hash the whole row: `Data.hashValue` looks only at a prefix.
        let rowBytes = width * 4
        rowIDs = bytes.withUnsafeBytes { raw in
            (0..<height).map { row in
                var hasher = Hasher()
                hasher.combine(bytes: UnsafeRawBufferPointer(rebasing: raw[(row * rowBytes)..<((row + 1) * rowBytes)]))
                return hasher.finalize()
            }
        }
        informativeRows = bytes.withUnsafeBytes { raw in
            let pixels = raw.bindMemory(to: UInt32.self)
            return (0..<height).map { row in
                let line = pixels[(row * width)..<((row + 1) * width)]
                return line.contains { $0 != line.first }
            }
        }
    }

    func viewport(at offset: Int, height rows: Int) -> ScrollingViewport? {
        let rowBytes = width * 4
        return ScrollingViewport(width: width, height: rows,
                                 pixels: bytes.subdata(in: (offset * rowBytes)..<((offset + rows) * rowBytes)))
    }

    /// Every step `delta` in 1..<viewport under which the viewports at `from` and `to` overlap
    /// with identical rows, and the overlap holds at least one row that isn't a flat colour. An
    /// overlap of flat background alone is no evidence: any delta would fit it.
    func evidencedDeltas(from: Int, to: Int, viewport: Int) -> [Int] {
        (1..<viewport).filter { delta in
            informativeRows[(from + delta)..<(from + viewport)].contains(true)
                && rowIDs[(from + delta)..<(from + viewport)].elementsEqual(rowIDs[to..<(to + viewport - delta)])
        }
    }

    /// Pixels alone can't settle this step: the true delta has no evidence, or another delta has as much.
    func isAmbiguous(from: Int, to: Int, viewport: Int) -> Bool {
        evidencedDeltas(from: from, to: to, viewport: viewport) != [to - from]
    }
}

/// What one scroll produced, compared with the page it came from.
struct ScrollRoundTrip {
    let expectedRows: Int
    /// Rows in the finished image, or nil when `finish()` delivered nothing.
    let producedRows: Int?
    /// First row that differs from the page, including a missing row at the end of a short image.
    let firstWrongRow: Int?
    /// Some viewport was answered with a reported alignment rejection.
    let reportedRejection: Bool
    let ambiguousSteps: [String]

    var isExact: Bool { producedRows == expectedRows && firstWrongRow == nil }
    /// Nothing delivered is wrong: either nothing was delivered or every delivered row is the page's.
    var deliveredOnlyPageRows: Bool {
        guard let producedRows else { return true }
        return firstWrongRow == nil || firstWrongRow! >= producedRows
    }
    /// Exact, or an ambiguous step was reported instead of being guessed.
    var isExactOrReportedAmbiguity: Bool { isExact || (reportedRejection && deliveredOnlyPageRows) }

    var summary: String {
        "produced \(producedRows.map(String.init) ?? "nothing") of \(expectedRows) rows, first wrong row "
            + "\(firstWrongRow.map(String.init) ?? "none"), rejection reported: \(reportedRejection), "
            + "ambiguous steps: \(ambiguousSteps.isEmpty ? "none" : ambiguousSteps.joined(separator: ", "))"
    }

    static func run(_ page: SyntheticScrollPage, offsets: [Int], viewport: Int,
                    sourceLocation: SourceLocation = #_sourceLocation) throws -> ScrollRoundTrip {
        let session = ScrollingCaptureSession(budget: ScrollingCaptureBudget(
            pixelCap: page.width * page.height * 2, memoryBudgetBytes: 2_000_000_000))
        var rejected = false
        for offset in offsets {
            let frame = try #require(page.viewport(at: offset, height: viewport), sourceLocation: sourceLocation)
            switch session.ingest(frame) {
            case .preview, .unchanged:
                break
            case .rejectedAlignment:
                rejected = true
            case let other:
                Issue.record("Fixture budget must not stop the scroll: \(other)", sourceLocation: sourceLocation)
            }
        }
        var ambiguous: [String] = []
        for (from, to) in zip(offsets, offsets.dropFirst()) where to > from {
            if page.isAmbiguous(from: from, to: to, viewport: viewport) {
                ambiguous.append("\(from)→\(to) fits \(page.evidencedDeltas(from: from, to: to, viewport: viewport))")
            }
        }
        let expected = (offsets.max() ?? 0) + viewport
        guard let png = session.finish()?.pngData else {
            return ScrollRoundTrip(expectedRows: expected, producedRows: nil, firstWrongRow: nil,
                                   reportedRejection: rejected, ambiguousSteps: ambiguous)
        }
        let image = try #require(decodedRGBA(png), sourceLocation: sourceLocation)
        try #require(image.width == page.width, sourceLocation: sourceLocation)
        let rowBytes = page.width * 4
        var firstWrong: Int?
        for row in 0..<min(image.height, expected)
        where !image.bytes[(row * rowBytes)..<((row + 1) * rowBytes)].elementsEqual(page.bytes[(row * rowBytes)..<((row + 1) * rowBytes)]) {
            firstWrong = row
            break
        }
        if firstWrong == nil, image.height != expected { firstWrong = min(image.height, expected) }
        return ScrollRoundTrip(expectedRows: expected, producedRows: image.height, firstWrongRow: firstWrong,
                               reportedRejection: rejected, ambiguousSteps: ambiguous)
    }

    private static func decodedRGBA(_ png: Data) -> (width: Int, height: Int, bytes: Data)? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var bytes = Data(count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                            | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? (image.width, image.height, bytes) : nil
    }
}

/// SplitMix64: a small deterministic generator, so every seed is the same scroll on every run.
struct SeededScroll: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct ScrollingRoundTripTests {
    private let harnessPage = SyntheticScrollPage()

    /// The oracle itself. A steady step has one evidenced delta. The live flick's true overlap is
    /// flat background, so only the wrong 40-row step has evidence (H6). On the periodic page a
    /// 420-row step also fits 20 rows; unique markers settle it.
    @Test func ambiguityOracleSeparatesEvidencedStepsFromPeriodicOnes() {
        #expect(harnessPage.evidencedDeltas(from: 0, to: 150, viewport: 530) == [150])
        #expect(harnessPage.evidencedDeltas(from: 0, to: 440, viewport: 530) == [40])
        #expect(harnessPage.isAmbiguous(from: 0, to: 440, viewport: 530))
        #expect(harnessPage.evidencedDeltas(from: 100, to: 520, viewport: 530) == [20, 420])
        let unique = SyntheticScrollPage(uniqueMarkers: true)
        #expect(unique.evidencedDeltas(from: 100, to: 520, viewport: 530) == [420])
        #expect(!unique.isAmbiguous(from: 100, to: 520, viewport: 530))
    }

    /// Live 2026-09-24: four ~150 px wheel steps lost rows at two seams and started blocks early.
    @Test func d3SteadyScrollReproducesThePageExactly() async throws {
        try await knownDefect("D3") {
            let run = try ScrollRoundTrip.run(harnessPage, offsets: [0, 150, 300, 450, 600], viewport: 530)
            #expect(run.isExact, "D3: steady scroll \(run.summary)")
        }
    }

    /// Live samples land mid-step: 250 ms sampling during a ~300 ms wheel scroll. On this page a
    /// few samples also fit a step 400 rows longer; CleanShot's stitch of the live page was exact,
    /// and so was a best-score matcher in the diagnosis (H5), so exact is required here.
    @Test func d3MidStepSamplesReproduceThePageExactly() async throws {
        try await knownDefect("D3") {
            let run = try ScrollRoundTrip.run(harnessPage, offsets: [0, 90, 150, 240, 300, 390, 450, 540, 600],
                                              viewport: 530)
            #expect(run.isExact, "D3: mid-step scroll \(run.summary)")
        }
    }

    /// Live: a flick gave 416 rows, less than one viewport. On a page that repeats every 400 rows,
    /// a 440-row flick overlaps only flat background, while a 40-row step matches block rows, so
    /// the session must report the step rather than guess.
    @Test func d3FlickOnAPeriodicPageIsExactOrReported() async throws {
        try await knownDefect("D3") {
            let run = try ScrollRoundTrip.run(harnessPage, offsets: [0, 440], viewport: 530)
            #expect(!run.ambiguousSteps.isEmpty, "the flick is genuinely ambiguous on this page")
            #expect(run.isExactOrReportedAmbiguity, "D3: periodic flick \(run.summary)")
        }
    }

    /// Content that repeats every 48 rows, scrolled 80 rows at a time: 32, 80, 128… all fit.
    @Test func d3PeriodicContentIsNeverSilentlyMisaligned() async throws {
        try await knownDefect("D3") {
            let session = ScrollingCaptureSession(budget: ScrollingCaptureBudget(pixelCap: 240 * 10_000,
                                                                                 memoryBudgetBytes: 2_000_000_000))
            var rejected = false
            for offset in [0, 80, 160] {
                let image = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 400,
                                                                                  logicalYOffset: offset, period: 48))
                if case .rejectedAlignment = session.ingest(try #require(ScrollingViewport(cgImage: image))) {
                    rejected = true
                }
            }
            let produced = session.finish().flatMap { CGImageSourceCreateWithData($0.pngData as CFData, nil) }
                .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
                .flatMap { $0[kCGImagePropertyPixelHeight] as? Int }
            #expect(produced == 560 || rejected,
                    "D3: an ambiguous 80-row step on 48-row periodic content produced \(produced.map(String.init) ?? "nothing") of 560 rows without reporting it")
        }
    }

    /// Round-trip property over seeded scrolls of a page with uniform bands, textured blocks that
    /// repeat every 400 rows, and unique markers: small, medium and flick-sized steps. An unambiguous scroll must come
    /// back exactly; an ambiguous one may instead be reported, but never delivered wrong.
    @Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8] as [UInt64])
    func d3RandomScrollsRoundTripExactly(seed: UInt64) async throws {
        try await knownDefect("D3") {
            let page = SyntheticScrollPage(width: 360, uniqueMarkers: true, texturedBlocks: true)
            var random = SeededScroll(seed: seed)
            let viewport = Int.random(in: 300...530, using: &random)
            var offsets = [0]
            while offsets.count < 12 {
                let step: Int
                switch Int.random(in: 0..<10, using: &random) {
                case 0..<5: step = Int.random(in: 1...60, using: &random)
                case 5..<8: step = Int.random(in: 61...200, using: &random)
                default: step = Int.random(in: 201...(viewport - 1), using: &random)
                }
                guard offsets.last! + step + viewport <= page.height else { break }
                offsets.append(offsets.last! + step)
            }
            let run = try ScrollRoundTrip.run(page, offsets: offsets, viewport: viewport)
            if run.ambiguousSteps.isEmpty {
                #expect(run.isExact, "D3: seed \(seed), viewport \(viewport), offsets \(offsets): \(run.summary)")
            } else {
                #expect(run.isExactOrReportedAmbiguity,
                        "D3: seed \(seed), viewport \(viewport), offsets \(offsets): \(run.summary)")
            }
        }
    }
}
