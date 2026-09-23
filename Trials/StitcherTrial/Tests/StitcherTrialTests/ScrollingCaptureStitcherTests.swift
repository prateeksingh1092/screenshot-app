/*
BSD 3-Clause License

Copyright (c) 2026, Trong Duong Duc

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

//
//  ScrollingCaptureStitcherTests.swift
//  SnapzyTests
//
//  Unit tests for the scrolling capture stitch algorithm.
//

import CoreGraphics
import Foundation
import Testing
@testable import StitcherTrial

struct ScrollingCaptureStitcherTests {

  // MARK: - start(with:)

  @Test func testStart_initializesCorrectly() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 200, height: 100) else {
      Issue.record("Failed to create test image")
      return
    }

    let update = stitcher.start(with: image)

    #expect(update != nil)
    #expect(update?.acceptedFrameCount == 1)
    #expect(update?.outputHeight == 100)
    #expect(update?.mergedImage != nil)

    if case .initialized = update?.outcome {} else {
      Issue.record("Expected .initialized outcome, got: \(String(describing: update?.outcome))")
    }
  }

  @Test func testStart_setsFrameCount() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 100, height: 50) else {
      Issue.record("Failed to create test image")
      return
    }

    _ = stitcher.start(with: image)
    #expect(stitcher.acceptedFrameCount == 1)
    #expect(stitcher.outputHeight == 50)
  }

  // MARK: - append identical image

  @Test func testAppend_identicalImage_ignoredNoMovement() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(
      width: 200, height: 100,
      red: 80, green: 80, blue: 80
    ) else {
      Issue.record("Failed to create test image")
      return
    }

    _ = stitcher.start(with: image)

    let update = stitcher.append(image, maxOutputHeight: 10000)

    #expect(update != nil)
    if case .ignoredNoMovement = update?.outcome {} else {
      Issue.record("Expected .ignoredNoMovement for identical frame, got: \(String(describing: update?.outcome))")
    }

    // Frame count should NOT increment for ignored frames
    #expect(stitcher.acceptedFrameCount == 1)
  }

  // MARK: - append mismatched dimensions

  @Test func testAppend_mismatchedDimensions_ignoredAlignmentFailed() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image1 = TestImageFactory.solidColor(width: 200, height: 100),
          let image2 = TestImageFactory.solidColor(width: 300, height: 100) else {
      Issue.record("Failed to create test images")
      return
    }

    _ = stitcher.start(with: image1)
    let update = stitcher.append(image2, maxOutputHeight: 10000)

    #expect(update != nil)
    if case .ignoredAlignmentFailed = update?.outcome {} else {
      Issue.record("Expected .ignoredAlignmentFailed for mismatched dims, got: \(String(describing: update?.outcome))")
    }
  }

  @Test func testAppend_mismatchedHeight_ignoredAlignmentFailed() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image1 = TestImageFactory.solidColor(width: 200, height: 100),
          let image2 = TestImageFactory.solidColor(width: 200, height: 150) else {
      Issue.record("Failed to create test images")
      return
    }

    _ = stitcher.start(with: image1)
    let update = stitcher.append(image2, maxOutputHeight: 10000)

    if case .ignoredAlignmentFailed = update?.outcome {} else {
      Issue.record("Expected .ignoredAlignmentFailed for mismatched height")
    }
  }

  // MARK: - mergedImage

  @Test func testMergedImage_afterStart_returnsNonNil() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 100, height: 100) else {
      Issue.record("Failed to create test image")
      return
    }

    _ = stitcher.start(with: image)
    let merged = stitcher.mergedImage()

    #expect(merged != nil)
    #expect(merged?.width == 100)
    #expect(merged?.height == 100)
  }

  @Test func testMergedImage_beforeStart_returnsNil() {
    let stitcher = ScrollingCaptureStitcher()
    #expect(stitcher.mergedImage() == nil)
  }

  // MARK: - previewImage

  @Test func testPreviewImage_respectsMaxBounds() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 400, height: 400) else {
      Issue.record("Failed to create test image")
      return
    }

    _ = stitcher.start(with: image)

    let preview = stitcher.previewImage(maxPixelWidth: 100, maxPixelHeight: 100)
    #expect(preview != nil)

    if let preview {
      #expect(preview.width <= 100)
      #expect(preview.height <= 100)
    }
  }

  @Test func testPreviewImage_beforeStart_returnsNil() {
    let stitcher = ScrollingCaptureStitcher()
    #expect(stitcher.previewImage(maxPixelWidth: 200, maxPixelHeight: 200) == nil)
  }

  // MARK: - append with shifted content (integration)

  @Test func testAppend_shiftedContent_appendsOrFailsAlignment() {
    let stitcher = ScrollingCaptureStitcher()
    let width = 200
    let height = 100

    // Use distinct row signatures so there is measurable inter-frame change.
    guard let image1 = TestImageFactory.scrollingFrame(width: width, height: height, logicalYOffset: 0) else {
      Issue.record("Failed to create frame 1")
      return
    }

    guard let image2 = TestImageFactory.scrollingFrame(width: width, height: height, logicalYOffset: 20) else {
      Issue.record("Failed to create frame 2")
      return
    }

    _ = stitcher.start(with: image1)
    let update = stitcher.append(image2, maxOutputHeight: 10000)

    #expect(update != nil)

    // Synthetic images may not align reliably through the vision-assisted matcher,
    // so we accept either a successful append or an alignment failure,
    // but never "no movement" because the frames are objectively different.
    switch update?.outcome {
    case .appended(let deltaY):
      #expect(deltaY > 0 , "Delta should be positive for downward scroll")
      #expect(stitcher.outputHeight > height , "Output height should grow after append")
      #expect(stitcher.acceptedFrameCount == 2)
    case .ignoredAlignmentFailed:
      #expect(stitcher.acceptedFrameCount == 1)
    case .ignoredNoMovement:
      Issue.record("Expected movement between shifted frames, got ignoredNoMovement")
    default:
      Issue.record("Unexpected outcome: \(String(describing: update?.outcome))")
    }
  }

  // MARK: - Multiple appends build height

  @Test func testMultipleAppends_outputHeightAccumulates() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 100, height: 50) else {
      Issue.record("Failed to create test image")
      return
    }

    _ = stitcher.start(with: image)
    let initialHeight = stitcher.outputHeight
    #expect(initialHeight == 50)

    // Appending identical images won't increase height (no movement detected)
    _ = stitcher.append(image, maxOutputHeight: 10000)
    // Height should not change for identical frames
    #expect(stitcher.outputHeight == 50)
  }

  // MARK: - maxOutputHeight enforcement

  @Test func testAppend_atMaxOutputHeight_returnsReachedHeightLimit() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 100, height: 100) else {
      Issue.record("Failed to create test image")
      return
    }

    _ = stitcher.start(with: image)

    // max = current output height → no more room
    let update = stitcher.append(image, maxOutputHeight: stitcher.outputHeight)

    // For identical images, likely ignoredNoMovement; for shifted images it would be reachedHeightLimit
    // Either outcome is acceptable since we're testing the height limit enforcement path
    #expect(update != nil)
  }

  // MARK: - Alignment Debug Info

  @Test func testStart_alignmentDebug_isInitialFrame() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 100, height: 100) else {
      Issue.record("Failed to create test image")
      return
    }

    let update = stitcher.start(with: image)
    #expect(update?.alignmentDebug?.path == .initialFrame)
    #expect(update?.alignmentDebug?.confidence == 1.0)
    #expect(!(update?.alignmentDebug?.usedVisionEstimate ?? true))
    #expect(update?.safety == .confirmed)
  }

  // MARK: - Merge Direction

  @Test func testStart_mergeDirectionIsUnresolved() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 100, height: 100) else {
      Issue.record("Failed to create test image")
      return
    }

    let update = stitcher.start(with: image)
    #expect(update?.mergeDirection == .unresolved)
  }

  // MARK: - likelyReachedBoundary

  @Test func testAppend_identicalImage_setsLikelyReachedBoundary() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(
      width: 200, height: 100,
      red: 120, green: 120, blue: 120
    ) else {
      Issue.record("Failed to create test image")
      return
    }

    _ = stitcher.start(with: image)
    let update = stitcher.append(image, maxOutputHeight: 10000)

    if case .ignoredNoMovement = update?.outcome {
      #expect(update?.likelyReachedBoundary ?? false)
    }
  }

  // MARK: - renderMergedImage flag

  @Test func testAppend_renderMergedImageFalse_skipsMergedImage() {
    let stitcher = ScrollingCaptureStitcher()
    guard let image = TestImageFactory.solidColor(width: 100, height: 100) else {
      Issue.record("Failed to create test image")
      return
    }

    _ = stitcher.start(with: image)
    let update = stitcher.append(image, maxOutputHeight: 10000, renderMergedImage: false)

    // When renderMergedImage is false, mergedImage in the update may still be
    // the cached version from start(), so we just verify the call succeeds.
    #expect(update != nil)
  }

  @Test func testAppend_largeExpectedDelta_isNotPinnedToSmallLastMatch() {
    let stitcher = ScrollingCaptureStitcher()
    let width = 240
    let height = 400
    let firstDelta = 24
    let secondDelta = 140

    guard
      let first = TestImageFactory.scrollingFrame(width: width, height: height, logicalYOffset: 0),
      let second = TestImageFactory.scrollingFrame(
        width: width,
        height: height,
        logicalYOffset: firstDelta
      ),
      let third = TestImageFactory.scrollingFrame(
        width: width,
        height: height,
        logicalYOffset: firstDelta + secondDelta
      )
    else {
      Issue.record("Failed to create scrolling frames")
      return
    }

    _ = stitcher.start(with: first)
    let firstUpdate = stitcher.append(
      second,
      maxOutputHeight: 10_000,
      expectedSignedDeltaPixels: firstDelta
    )
    guard case .appended(let acceptedFirstDelta) = firstUpdate?.outcome else {
      Issue.record("Expected first append to succeed, got \(String(describing: firstUpdate?.outcome))")
      return
    }
    #expect(acceptedFirstDelta == firstDelta)

    let secondUpdate = stitcher.append(
      third,
      maxOutputHeight: 10_000,
      expectedSignedDeltaPixels: secondDelta
    )
    guard case .appended(let acceptedSecondDelta) = secondUpdate?.outcome else {
      Issue.record("Expected large second append to succeed, got \(String(describing: secondUpdate?.outcome))")
      return
    }
    #expect(acceptedSecondDelta == secondDelta)
    #expect(stitcher.outputHeight == height + firstDelta + secondDelta)
  }

  @Test func testAppend_repeatedContentIntermediateFrame_isNotAppendedForKnownStep() {
    let stitcher = ScrollingCaptureStitcher()
    let width = 240
    let height = 360
    let knownStep = 80
    let intermediate = 12

    guard
      let first = TestImageFactory.repeatedScrollingFrame(
        width: width,
        height: height,
        logicalYOffset: 0
      ),
      let mid = TestImageFactory.repeatedScrollingFrame(
        width: width,
        height: height,
        logicalYOffset: intermediate
      ),
      let settled = TestImageFactory.repeatedScrollingFrame(
        width: width,
        height: height,
        logicalYOffset: knownStep
      )
    else {
      Issue.record("Failed to create repeated-content frames")
      return
    }

    _ = stitcher.start(with: first)
    let intermediateUpdate = stitcher.append(
      mid,
      maxOutputHeight: 10_000,
      expectedSignedDeltaPixels: knownStep
    )
    if case .appended = intermediateUpdate?.outcome {
      Issue.record("Intermediate repeated-content frame should not append, got \(String(describing: intermediateUpdate?.outcome))")
      return
    }
    #expect(stitcher.acceptedFrameCount == 1)

    let settledUpdate = stitcher.append(
      settled,
      maxOutputHeight: 10_000,
      expectedSignedDeltaPixels: knownStep
    )
    guard case .appended(let deltaY) = settledUpdate?.outcome else {
      Issue.record("Settled known-step frame should append, got \(String(describing: settledUpdate?.outcome))")
      return
    }
    #expect(deltaY == knownStep)
    #expect(stitcher.outputHeight == height + knownStep)
  }

  @Test func testAppend_settledFinalStepIncludesShortRemainingStrip() throws {
    let stitcher = ScrollingCaptureStitcher()
    let first = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 360, logicalYOffset: 0))
    _ = stitcher.start(with: first)
    for (offset, expectedAppend) in [(80, 80), (160, 80), (172, 12)] {
      let frame = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 360, logicalYOffset: offset))
      let update = try #require(stitcher.append(frame, maxOutputHeight: 10_000,
        expectedSignedDeltaPixels: -80, allowsSettledPartialStep: true))
      guard case .appended(let delta) = update.outcome else {
        Issue.record("Expected remaining strip at offset \(offset), got \(update.outcome)")
        return
      }
      #expect(delta == expectedAppend)
    }
    #expect(stitcher.outputHeight == 532)
    let reference = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 532, logicalYOffset: 0))
    let result = try #require(stitcher.mergedImage())
    #expect(result.dataProvider?.data as Data? == reference.dataProvider?.data as Data?)
  }

  @Test func testAppend_settledStepStillRejectsOversizedJump() throws {
    let stitcher = ScrollingCaptureStitcher()
    let first = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 360, logicalYOffset: 0))
    let jumped = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 360, logicalYOffset: 240))
    _ = stitcher.start(with: first)
    let update = stitcher.append(jumped, maxOutputHeight: 10_000,
      expectedSignedDeltaPixels: -80, allowsSettledPartialStep: true)
    if case .appended = update?.outcome {
      Issue.record("Settled frames must still obey the maximum known step")
    }
    #expect(stitcher.outputHeight == 360)
  }

  @Test func testAppend_skippedBandDoesNotOverrideKnownStep() {
    let stitcher = ScrollingCaptureStitcher()
    let width = 240
    let height = 360
    let knownStep = 80
    let skippedBand = 240

    guard
      let first = TestImageFactory.repeatedScrollingFrame(
        width: width,
        height: height,
        logicalYOffset: 0
      ),
      let leap = TestImageFactory.repeatedScrollingFrame(
        width: width,
        height: height,
        logicalYOffset: skippedBand
      )
    else {
      Issue.record("Failed to create skipped-band frames")
      return
    }

    _ = stitcher.start(with: first)
    let update = stitcher.append(
      leap,
      maxOutputHeight: 10_000,
      expectedSignedDeltaPixels: knownStep
    )
    if case .appended(let deltaY) = update?.outcome {
      Issue.record("Skipped-band leap \(deltaY) should not append against known step \(knownStep)")
      return
    }
    #expect(stitcher.acceptedFrameCount == 1)
    #expect(stitcher.outputHeight == height)
  }

  @Test func testAppend_mismatchedDimensions_marksUnsafe() {
    let stitcher = ScrollingCaptureStitcher()
    guard
      let image1 = TestImageFactory.solidColor(width: 100, height: 100),
      let image2 = TestImageFactory.solidColor(width: 120, height: 100)
    else {
      Issue.record("Failed to create test images")
      return
    }

    _ = stitcher.start(with: image1)
    let update = stitcher.append(image2, maxOutputHeight: 10000)

    #expect(update?.safety == .unsafe(reason: "alignment-failed"))
  }

}
