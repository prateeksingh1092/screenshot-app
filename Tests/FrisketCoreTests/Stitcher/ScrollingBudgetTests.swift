import Foundation
import Testing
import FrisketCore

/// A page as wide as a 5K display at 2×. Each row is runs of 2–16 same-coloured pixels, so it
/// compresses about as well as ordinary screen content (a few to one), and its first pixel
/// encodes the row number, so no two rows match and there is exactly one correct step.
private struct RetinaPage {
    static let width = 5_120

    static func rows(from top: Int, count: Int) -> Data {
        var bytes = Data(count: width * count * 4)
        bytes.withUnsafeMutableBytes { raw in
            let pixels = raw.bindMemory(to: UInt32.self)
            for row in 0..<count {
                let y = top + row
                var random = SeededScroll(seed: UInt64(y) &* 0x2545_F491_4F6C_DD1D &+ 1)
                let line = UnsafeMutableBufferPointer(rebasing: pixels[(row * width)..<((row + 1) * width)])
                line[0] = UInt32(y & 0xFF) | UInt32((y >> 8) & 0xFF) << 8 | 0x5A << 16 | 255 << 24
                var x = 1
                while x < width {
                    let run = min(Int.random(in: 2...16, using: &random), width - x)
                    let colour = UInt32(truncatingIfNeeded: random.next()) | 255 << 24
                    UnsafeMutableBufferPointer(rebasing: line[x..<(x + run)]).initialize(repeating: colour)
                    x += run
                }
            }
        }
        return bytes
    }
}

struct ScrollingBudgetTests {
    /// D20: the scrolling budget charges raw frames against an *encoded* ceiling. Two raw
    /// 5,120 × 2,880 viewports (the previous one plus the new one) are already 118 MB of v1's
    /// 128 MiB, so a 5K Retina capture stops after about two screens with `.encodedCeiling`,
    /// long before the pixel cap.
    ///
    /// The frames, the encoded ceiling and the memory budget are v1's. Only the pixel cap is
    /// lowered, to six viewports, so the run stays short once the defect is fixed; D20 is about
    /// the budget stopping first, not about the cap's value (DA-6 sets that to 32,768 px).
    @Test func d20FiveKRetinaScrollReachesThePixelCapWithoutABudgetStop() async throws {
        try await knownDefect("D20") {
            let viewport = 2_880, step = 2_560
            let capRows = viewport + 5 * step
            let v1 = ScrollingCaptureBudget.v1
            let session = ScrollingCaptureSession(budget: ScrollingCaptureBudget(
                pixelCap: RetinaPage.width * capRows, memoryBudgetBytes: v1.memoryBudgetBytes,
                encodedByteCeiling: v1.encodedByteCeiling))
            var rows = 0
            var stop: ScrollingCaptureNotice?
            var frames = 0
            while stop == nil, frames < 8 {
                let frame = try #require(ScrollingViewport(width: RetinaPage.width, height: viewport,
                                                          pixels: RetinaPage.rows(from: frames * step, count: viewport)))
                frames += 1
                switch session.ingest(frame) {
                case let .preview(preview):
                    rows = preview.height
                case let .stopped(notice, preview):
                    stop = notice
                    rows = preview.height
                case let .refused(notice):
                    stop = notice
                case let other:
                    Issue.record("Every 5K step fits exactly one delta; ingest answered \(other)")
                    return
                }
            }
            session.cancel()
            #expect(stop == .pixelCap && rows == capRows,
                    "D20: a 5,120 × 2,880 scroll stopped with \(stop.map { "\($0)" } ?? "nothing") at \(rows) of \(capRows) rows after \(frames) viewports")
        }
    }
}
