import CoreGraphics
import Foundation

/// One in-memory viewport in a downward Scrolling capture.
public struct ScrollingCaptureFrame {
  public let image: CGImage
  /// Optional known scroll distance, in pixels. Omit for manual scrolling.
  public let expectedVerticalStep: Int?

  /// True only when the viewport has settled; permits a verified short final step.
  public let isSettled: Bool

  public init(image: CGImage, expectedVerticalStep: Int? = nil, isSettled: Bool = false) {
    self.isSettled = isSettled
    self.image = image
    self.expectedVerticalStep = expectedVerticalStep
  }
}

/// Alignment evidence in input order; contains no pixels or free-form diagnostics.
public struct ScrollingCaptureAlignment: Equatable, Sendable {
  public enum Disposition: Equatable, Sendable {
    case initialFrame, appended, noMovement, rejectedAlignment
  }
  public let disposition: Disposition
  public let pixelScore: Double?
  public let totalScore: Double?
  public let appendedRows: Int
  public let confidence: Double
  public let usedVisionEstimate: Bool
}

/// An immutable, strip-backed image independent of the input frames.
public struct StitchedCapture {
  public let image: CGImage
  public let alignments: [ScrollingCaptureAlignment]
}

public enum StitchingFailure: Error, Equatable {
  case emptySequence
  case imageUnavailable
  case invalidFrame
}

public enum Stitcher {
  /// Consumes the sequence once, retaining only the previous accepted raster and
  /// compressed output strips. Use a lazy sequence to release viewports promptly.
  /// Detected static headers/footers are excluded after movement. No disk I/O.
  public static func stitch<Frames: Sequence>(_ frames: Frames) throws -> StitchedCapture
  where Frames.Element == ScrollingCaptureFrame {
    let matcher = ScrollingCaptureStitcher()
    var iterator = frames.makeIterator()
    var dimensions: (width: Int, height: Int)?
    var alignments: [ScrollingCaptureAlignment] = []
    while try autoreleasepool(invoking: {
      guard let frame = iterator.next() else { return false }
      if let step = frame.expectedVerticalStep, !(1..<frame.image.height).contains(step) {
        throw StitchingFailure.invalidFrame
      }
      if let dimensions, (frame.image.width != dimensions.width || frame.image.height != dimensions.height) {
        throw StitchingFailure.invalidFrame
      }
      dimensions = (frame.image.width, frame.image.height)
      let update = alignments.isEmpty
        ? matcher.start(with: frame.image)
        : matcher.append(frame.image, maxOutputHeight: Int.max,
            expectedSignedDeltaPixels: frame.expectedVerticalStep, renderMergedImage: false,
            allowsSettledPartialStep: frame.isSettled)
      guard let update else { throw StitchingFailure.imageUnavailable }
      let rows: Int
      let disposition: ScrollingCaptureAlignment.Disposition
      switch update.outcome {
      case .initialized: rows = update.outputHeight; disposition = .initialFrame
      case .appended(let delta): rows = delta; disposition = .appended
      case .ignoredNoMovement: rows = 0; disposition = .noMovement
      default: rows = 0; disposition = .rejectedAlignment
      }
      alignments.append(ScrollingCaptureAlignment(disposition: disposition,
        pixelScore: update.alignmentDebug?.pixelScore, totalScore: update.alignmentDebug?.totalScore,
        appendedRows: rows,
        confidence: update.alignmentDebug?.confidence ?? 0,
        usedVisionEstimate: update.alignmentDebug?.usedVisionEstimate ?? false))
      return true
    }) {}
    guard !alignments.isEmpty else { throw StitchingFailure.emptySequence }
    guard let image = matcher.mergedImage() else { throw StitchingFailure.imageUnavailable }
    return StitchedCapture(image: image, alignments: alignments)
  }
}
