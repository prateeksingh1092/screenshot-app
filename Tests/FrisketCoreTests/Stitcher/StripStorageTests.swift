import CoreGraphics
import Foundation
import Testing
@testable import FrisketCore

struct StripStorageTests {
  @Test func initialFrameStreamsFixedSizeStripsWithoutChangingPixels() throws {
    let stitcher = ScrollingCaptureStitcher()
    let frame = try #require(TestImageFactory.scrollingFrame(width: 240, height: 600, logicalYOffset: 0))
    _ = try #require(stitcher.start(with: frame))
    var heights: [Int] = []
    var bytes = Data()
    try stitcher.forEachStrip { strip in
      #expect(strip.width == 240)
      heights.append(strip.height)
      bytes.append(try #require(strip.dataProvider?.data as Data?))
    }
    #expect(heights == [256, 256, 88])
    #expect(bytes == frame.dataProvider?.data as Data?)
  }
  @Test func doesNotRetainCallerFrameAfterCopyingRows() throws {
    let stitcher = ScrollingCaptureStitcher()
    weak var input: CGImage?
    try autoreleasepool {
      let frame = try #require(TestImageFactory.scrollingFrame(width: 240, height: 400))
      input = frame
      _ = try #require(stitcher.start(with: frame))
    }
    #expect(input == nil)
    #expect(stitcher.mergedImage()?.height == 400)
  }

  @Test func stickyHeaderAndFooterAreExcludedAtExactRowBoundaries() throws {
    let stitcher = ScrollingCaptureStitcher()
    _ = try #require(stitcher.start(with: stickyFrame(offset: 0)))
    for offset in [80, 160] {
      let update = try #require(stitcher.append(stickyFrame(offset: offset),
        maxOutputHeight: 2000, expectedSignedDeltaPixels: 80, renderMergedImage: false))
      #expect(update.alignmentDebug?.appendDeltaY == 80)
    }
    let reference = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 560, logicalYOffset: 0))
    var bytes = Data()
    try stitcher.forEachStrip { bytes.append(try #require($0.dataProvider?.data as Data?)) }
    #expect(stitcher.outputHeight == 560)
    #expect(bytes == reference.dataProvider?.data as Data?)
  }


  @Test func successiveFramesStreamOnlyNewRowsBeyondInitialOverlap() throws {
    let stitcher = ScrollingCaptureStitcher()
    let initial = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 400, logicalYOffset: 0))
    _ = try #require(stitcher.start(with: initial))
    var frozenStrip: CGImage?
    try stitcher.forEachStrip { if frozenStrip == nil { frozenStrip = $0 } }
    let frozenBytes = frozenStrip?.dataProvider?.data as Data?
    // Final frame has no overlap with the initial frame: alignment must advance.
    for offset in stride(from: 140, through: 700, by: 140) {
      weak var input: CGImage?
      try autoreleasepool {
        let frame = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 400, logicalYOffset: offset))
        input = frame
        let update = try #require(stitcher.append(frame, maxOutputHeight: 2000,
          expectedSignedDeltaPixels: 140, renderMergedImage: false))
        #expect(update.alignmentDebug?.appendDeltaY == 140)
        #expect(update.mergedImage == nil)
      }
      #expect(input == nil)
    }
    var heights: [Int] = [], bytes = Data()
    try stitcher.forEachStrip {
      heights.append($0.height)
      bytes.append(try #require($0.dataProvider?.data as Data?))
    }
    let reference = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 1100, logicalYOffset: 0))
    #expect(heights == [256, 256, 256, 256, 76])
    #expect(bytes == reference.dataProvider?.data as Data?)
    #expect(frozenStrip?.dataProvider?.data as Data? == frozenBytes)
    #expect(stitcher.acceptedFrameCount == 6)
  }


  @Test func outputSnapshotSurvivesAppendRestartAndStitcherRelease() throws {
    let original = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 400, logicalYOffset: 0))
    let snapshot: CGImage = try autoreleasepool {
      let stitcher = ScrollingCaptureStitcher()
      _ = try #require(stitcher.start(with: original))
      let snapshot = try #require(stitcher.mergedImage())
      let next = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 400, logicalYOffset: 80))
      _ = try #require(stitcher.append(next, maxOutputHeight: 2000, expectedSignedDeltaPixels: 80))
      _ = try #require(stitcher.start(with: next))
      return snapshot
    }
    for _ in 0..<2 {
      #expect(snapshot.dataProvider?.data as Data? == original.dataProvider?.data as Data?)
    }
  }

  private func stickyFrame(offset: Int) throws -> CGImage {
    let body = try #require(TestImageFactory.repeatedScrollingFrame(width: 240, height: 400, logicalYOffset: offset))
    let header = try #require(TestImageFactory.solidColor(width: 240, height: 31, red: 11, green: 22, blue: 33))
    let footer = try #require(TestImageFactory.solidColor(width: 240, height: 27, red: 44, green: 55, blue: 66))
    var data = try #require(header.dataProvider?.data as Data?)
    data.append(try #require(body.dataProvider?.data as Data?))
    data.append(try #require(footer.dataProvider?.data as Data?))
    let provider = try #require(CGDataProvider(data: data as CFData))
    return try #require(CGImage(width: 240, height: 458, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: 960, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: body.bitmapInfo,
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
  }

}
