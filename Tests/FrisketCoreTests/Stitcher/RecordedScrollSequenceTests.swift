import CoreGraphics
import Foundation
import Testing
import FrisketCore

private let fixtures = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .appendingPathComponent("Fixtures/ScrollingCapture")

struct RecordedScrollSequenceTests {
  @Test func syntheticRecordingFormatPreservesStickyContentAndDetectsDuplicatedBands() throws {
    let sequence = try RecordedScrollSequence.load(at: fixtures.appendingPathComponent("synthetic-sticky"))
    let result = try Stitcher.stitch(sequence.frames)
    #expect(try sequence.validationIssues(for: result.image).isEmpty)
    #expect(try sequence.rgba(result.image) == sequence.rgba(sequence.reference))
    print("RECORDING_FIXTURE synthetic vision_estimates=\(result.alignments.filter(\.usedVisionEstimate).count)")

    // Deliberately duplicate the first 16 rows over the next 16 without changing
    // height. The property oracle must detect a seam error even at exact height.
    var damaged = try sequence.rgba(sequence.reference)
    let bandBytes = sequence.reference.width * 4 * 16
    damaged.replaceSubrange(bandBytes..<(bandBytes * 2), with: damaged.prefix(bandBytes))
    let provider = try #require(CGDataProvider(data: damaged as CFData))
    let duplicate = try #require(CGImage(width: sequence.reference.width, height: sequence.reference.height,
      bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: sequence.reference.width * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: sequence.reference.bitmapInfo,
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    #expect(try sequence.validationIssues(for: duplicate).contains { $0.contains("band occurrences") })
    let cropped = try #require(sequence.reference.cropping(to: CGRect(x: 0, y: 0,
      width: sequence.reference.width, height: sequence.reference.height - 40)))
    #expect(try sequence.validationIssues(for: cropped).contains("height outside tolerance"))
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["FRISKET_RECORDED_SCROLLS"] == "1"))
  func recordedScrollSequences() throws {
    let folder = fixtures.appendingPathComponent("recordings")
    let cases = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
      .filter { $0.hasDirectoryPath && !$0.lastPathComponent.hasPrefix(".") }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    try #require(!cases.isEmpty, "Pending Prateek-authorized recordings; empty coverage cannot pass")
    for path in cases {
      let sequence = try RecordedScrollSequence.load(at: path)
      try #require(sequence.isRecorded, "Real-sequence gate requires recorded provenance")
      let result = try Stitcher.stitch(sequence.frames)
      #expect(try sequence.validationIssues(for: result.image).isEmpty)
      print("RECORDING_FIXTURE \(path.lastPathComponent) vision_estimates=\(result.alignments.filter(\.usedVisionEstimate).count)")
    }
  }
}
