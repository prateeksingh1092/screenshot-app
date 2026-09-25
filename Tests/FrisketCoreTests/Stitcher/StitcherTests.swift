import CoreGraphics
import Foundation
import Testing
import FrisketCore

struct StitcherTests {
  @Test func frameSequenceProducesIndependentByteExactImage() throws {
    let frames = try [0, 80, 160].map { offset in
      ScrollingCaptureFrame(image: try #require(TestImageFactory.scrollingFrame(
        width: 240, height: 400, logicalYOffset: offset)), expectedVerticalStep: 80)
    }
    let result = try Stitcher.stitch(frames)
    let reference = try #require(TestImageFactory.scrollingFrame(width: 240, height: 560, logicalYOffset: 0))
    #expect(result.image.width == 240)
    #expect(result.image.height == 560)
    #expect(result.image.dataProvider?.data as Data? == reference.dataProvider?.data as Data?)
    #expect(result.alignments.map(\.appendedRows) == [400, 80, 80])
    #expect(result.alignments.allSatisfy { $0.confidence > 0 })
    print("STITCHER_TEST vision_estimates=\(result.alignments.filter(\.usedVisionEstimate).count)")
  }
  @Test func settledFinalStepPreservesEveryRemainingRow() throws {
    let frames = try [0, 80, 160, 172].map { offset in
      ScrollingCaptureFrame(image: try #require(TestImageFactory.scrollingFrame(
        width: 240, height: 360, logicalYOffset: offset)), expectedVerticalStep: 80,
        isSettled: true)
    }
    let result = try Stitcher.stitch(frames)
    let reference = try #require(TestImageFactory.scrollingFrame(
      width: 240, height: 532, logicalYOffset: 0))
    #expect(result.image.height == 532)
    #expect(result.image.dataProvider?.data as Data? == reference.dataProvider?.data as Data?)
    #expect(result.alignments.map(\.appendedRows) == [360, 80, 80, 12])
  }
  @Test func rejectedIntermediateIsReportedAndDoesNotReplaceAcceptedFrame() throws {
    let frames = try [0, 12, 80, 80].map { offset in
      ScrollingCaptureFrame(image: try #require(TestImageFactory.scrollingFrame(
        width: 240, height: 360, logicalYOffset: offset)), expectedVerticalStep: 80)
    }
    let result = try Stitcher.stitch(frames)
    #expect(result.alignments.map(\.disposition) == [.initialFrame, .rejectedAlignment, .appended, .noMovement])
    #expect(result.alignments[2].pixelScore != nil)
    #expect(result.alignments[2].totalScore != nil)
    let reference = try #require(TestImageFactory.scrollingFrame(
      width: 240, height: 440, logicalYOffset: 0))
    #expect(result.image.dataProvider?.data as Data? == reference.dataProvider?.data as Data?)
  }
  @Test func malformedFrameSequenceFailsExplicitly() throws {
    let image = try #require(TestImageFactory.solidColor(width: 100, height: 100))
    for step in [0, -1, Int.min, Int.max, 100] {
      #expect(throws: StitchingFailure.invalidFrame) {
        try Stitcher.stitch([ScrollingCaptureFrame(image: image, expectedVerticalStep: step)])
      }
    }
    let otherSize = try #require(TestImageFactory.solidColor(width: 120, height: 100))
    #expect(throws: StitchingFailure.invalidFrame) {
      try Stitcher.stitch([ScrollingCaptureFrame(image: image), ScrollingCaptureFrame(image: otherSize)])
    }
    #expect(throws: StitchingFailure.emptySequence) {
      try Stitcher.stitch([ScrollingCaptureFrame]())
    }
  }
  @Test func manualScrollingConsumesFramesLazilyAndReleasesInputs() throws {
    weak var previous: CGImage?
    var made = 0
    let frames = stride(from: 0, through: 700, by: 140).lazy.compactMap { offset -> ScrollingCaptureFrame? in
      #expect(previous == nil)
      guard let image = TestImageFactory.scrollingFrame(width: 240, height: 400, logicalYOffset: offset)
        else { Issue.record("Synthetic frame allocation failed"); return nil }
      previous = image
      made += 1
      return ScrollingCaptureFrame(image: image)
    }
    let result = try Stitcher.stitch(frames)
    #expect(previous == nil)
    #expect(made == 6)
    #expect(result.image.height == 1100)
    let reference = try #require(TestImageFactory.scrollingFrame(
      width: 240, height: 1100, logicalYOffset: 0))
    #expect(result.image.dataProvider?.data as Data? == reference.dataProvider?.data as Data?)
    print("MANUAL_SCROLL_TEST vision_estimates=\(result.alignments.filter(\.usedVisionEstimate).count)")
  }
}
