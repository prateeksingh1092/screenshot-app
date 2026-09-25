import Foundation
import FrisketCore
import Testing

/// Ticket 90: editor open and Done became slow after the native renderer. The live repro is a
/// 400 × 500 pt capture on a 2× display (800 × 1,000 px) with one arrow and one label.
/// Each seam must finish inside its budget in a debug build (decision 70).
@Suite(.serialized) struct RenderTimingTests {
    static let budget: Duration = .milliseconds(250)

    static func liveEdits() throws -> DocumentEdits {
        let arrow = try #require(DocumentAnnotation(.arrow(x0: 40, y0: 450, x1: 320, y1: 447)))
        let label = try #require(DocumentAnnotation(.text(x: 20, y: 60, characters: "v2.1 $4.99 -10%")))
        return try #require(DocumentEdits(scale: 2, annotations: [arrow, label]))
    }

    /// Opaque noise, so the PNG is as hard to decode and encode as busy screen content (about 2.8 MB).
    static func base() throws -> (bitmap: Bitmap, png: Data) {
        var bytes = [UInt8](repeating: 255, count: 800 * 1000 * 4)
        var seed: UInt32 = 12_345
        for index in stride(from: 0, to: bytes.count, by: 4) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            bytes[index] = UInt8(truncatingIfNeeded: seed >> 24)
            bytes[index + 1] = UInt8(truncatingIfNeeded: seed >> 16)
            bytes[index + 2] = UInt8(truncatingIfNeeded: seed >> 8)
        }
        return (try #require(Bitmap(width: 800, height: 1000, bytes: bytes)),
                try CaptureRendererTests.encode(bytes, width: 800, height: 1000))
    }

    /// The fastest of three runs, so a busy machine does not fail the test on one slow run.
    static func fastest(_ body: () throws -> Void) rethrows -> Duration {
        let clock = ContinuousClock()
        var best = Duration.seconds(3600)
        for _ in 0..<3 { best = min(best, try clock.measure(body)) }
        return best
    }

    @Test func thePreviewRenderOfTheLiveReproIsInsideTheBudget() throws {
        let document = EditorDocument(base: try Self.base().bitmap, edits: try Self.liveEdits())
        let elapsed = Self.fastest { _ = DocumentRenderer.render(document) }
        #expect(elapsed <= Self.budget, "DocumentRenderer.render took \(elapsed) for 800 × 1,000 px")
    }

    @Test func flatteningTheLiveReproIsInsideTheBudget() throws {
        let png = try Self.base().png
        let edits = try Self.liveEdits()
        let elapsed = try Self.fastest { _ = try CaptureRenderer().flatten(png, edits: edits) }
        #expect(elapsed <= Self.budget, "CaptureRenderer.flatten took \(elapsed) for 800 × 1,000 px")
    }
}
