import CoreGraphics
import Foundation
import ImageIO

/// Budgets for one Scrolling capture.
///
/// `pixelCap` is the ticket 34 memory run's completed capture: 5,120 × 57,600
/// pixels. That run's peak physical footprint was 1,270,796,288 bytes, under
/// the 2,000,000,000 byte gate from ticket 05. `memoryBudgetBytes` is that gate.
/// Retained bytes are compressed strips plus the one previous viewport.
public struct ScrollingCaptureBudget: Equatable, Sendable {
  public let pixelCap: Int
  public let memoryBudgetBytes: Int

  public init(pixelCap: Int, memoryBudgetBytes: Int) {
    self.pixelCap = pixelCap
    self.memoryBudgetBytes = memoryBudgetBytes
  }

  public static let v1 = ScrollingCaptureBudget(pixelCap: 5_120 * 57_600, memoryBudgetBytes: 2_000_000_000)
}

public enum ScrollingCaptureNotice: Equatable, Sendable {
  case pixelCap
  case memoryBudget

  public var message: String {
    switch self {
    case .pixelCap:
      return "Scrolling capture stopped at the pixel limit. The image includes only the section that fit."
    case .memoryBudget:
      return "Scrolling capture stopped at the memory limit. The image includes only the section that fit."
    }
  }
}

/// Downsampled live preview. `width` and `height` are the pending original, not the preview bitmap.
public struct ScrollingPreview: Equatable, Sendable {
  public let pngData: Data
  public let width: Int
  public let height: Int
  public let notice: ScrollingCaptureNotice?

  public init(pngData: Data, width: Int, height: Int, notice: ScrollingCaptureNotice?) {
    self.pngData = pngData
    self.width = width
    self.height = height
    self.notice = notice
  }
}

/// One manual viewport. Pixels are tightly packed, 4 bytes per pixel, premultiplied RGBA, top row first.
public struct ScrollingViewport: Equatable, Sendable {
  public let width: Int
  public let height: Int
  public let pixels: Data

  public init?(width: Int, height: Int, pixels: Data) {
    guard width > 0, height > 0, pixels.count == width * height * 4 else { return nil }
    self.width = width
    self.height = height
    self.pixels = pixels
  }

  public init?(cgImage: CGImage) {
    let width = cgImage.width
    let height = cgImage.height
    guard width > 0, height > 0 else { return nil }
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
      guard let base = raw.baseAddress,
            let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
      else { return false }
      context.interpolationQuality = .none
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drew else { return nil }
    self.init(width: width, height: height, pixels: Data(pixels))
  }
}

public enum ScrollingFrameEvent: Equatable, Sendable {
  case viewport(ScrollingViewport)
  case done
  case cancel
  case failed(CaptureSourceFailure)
}

public protocol ScrollingFrameFeed: Sendable {
  func nextFrame() async -> ScrollingFrameEvent
}

public protocol ScrollingPreviewSurface: Sendable {
  func update(_ preview: ScrollingPreview) async
}

public enum ScrollingIngest: Equatable, Sendable {
  case preview(ScrollingPreview)
  case unchanged
  case rejectedAlignment(ScrollingCaptureAlignment)
  case stopped(ScrollingCaptureNotice, ScrollingPreview)
  case refused(ScrollingCaptureNotice)
  case failed
}

/// Pending original for one manual Scrolling capture. Frames are copied into compressed strips and then released.
/// Incremental matcher access is confined here for awaited frames, live previews and
/// per-frame budget stops; see the live-session exception in docs/stitcher.md.
public final class ScrollingCaptureSession: @unchecked Sendable {
  private let budget: ScrollingCaptureBudget
  private var matcher = ScrollingCaptureStitcher()
  private var notice: ScrollingCaptureNotice?
  private var rejection: ScrollingCaptureAlignment?

  public init(budget: ScrollingCaptureBudget) {
    self.budget = budget
  }

  public func ingest(_ viewport: ScrollingViewport) -> ScrollingIngest {
    if let rejection { return .rejectedAlignment(rejection) }
    if let notice {
      guard let preview = currentPreview(notice) else { return .refused(notice) }
      return .stopped(notice, preview)
    }
    let frameBytes = viewport.pixels.count
    let framePixels = viewport.width * viewport.height
    if matcher.acceptedFrameCount == 0 {
      if framePixels > budget.pixelCap { return .refused(.pixelCap) }
      if frameBytes > budget.memoryBudgetBytes { return .refused(.memoryBudget) }
    } else if matcher.retainedByteCount + frameBytes > budget.memoryBudgetBytes {
      self.notice = .memoryBudget
      guard let preview = currentPreview(.memoryBudget) else { return .refused(.memoryBudget) }
      return .stopped(.memoryBudget, preview)
    } else if matcher.pixelWidth > 0, matcher.outputHeight >= budget.pixelCap / matcher.pixelWidth {
      self.notice = .pixelCap
      guard let preview = currentPreview(.pixelCap) else { return .refused(.pixelCap) }
      return .stopped(.pixelCap, preview)
    }
    guard let image = cgImage(viewport) else { return .failed }
    let update: ScrollingCaptureStitchUpdate?
    if matcher.acceptedFrameCount == 0 {
      update = autoreleasepool { matcher.start(with: image) }
    } else {
      let maxHeight = budget.pixelCap / max(matcher.pixelWidth, 1)
      update = autoreleasepool {
        matcher.append(image, maxOutputHeight: maxHeight, renderMergedImage: false, allowsSettledPartialStep: false)
      }
    }
    guard let update else { return .failed }
    if matcher.retainedByteCount > budget.memoryBudgetBytes {
      cancel()
      return .refused(.memoryBudget)
    }
    switch update.outcome {
    case .initialized, .appended:
      guard let preview = currentPreview(nil) else { return .failed }
      return .preview(preview)
    case .reachedHeightLimit:
      notice = .pixelCap
      guard let preview = currentPreview(.pixelCap) else { return .refused(.pixelCap) }
      return .stopped(.pixelCap, preview)
    case .ignoredNoMovement:
      return .unchanged
    case .ignoredAlignmentFailed:
      let evidence = ScrollingCaptureAlignment(disposition: .rejectedAlignment,
        pixelScore: update.alignmentDebug?.pixelScore, totalScore: update.alignmentDebug?.totalScore,
        appendedRows: 0, confidence: update.alignmentDebug?.confidence ?? 0,
        usedVisionEstimate: update.alignmentDebug?.usedVisionEstimate ?? false)
      rejection = evidence
      matcher = ScrollingCaptureStitcher()
      return .rejectedAlignment(evidence)
    }
  }

  public func finish() -> CaptureImage? {
    guard rejection == nil else { return nil }
    guard matcher.acceptedFrameCount > 0, let image = matcher.mergedImage(), let png = encodePNG(image), !png.isEmpty else {
      cancel()
      return nil
    }
    cancel()
    return CaptureImage(pngData: png)
  }

  public func cancel() {
    matcher = ScrollingCaptureStitcher()
    notice = nil
    rejection = nil
  }

  private func currentPreview(_ notice: ScrollingCaptureNotice?) -> ScrollingPreview? {
    guard matcher.outputHeight > 0, let image = matcher.previewImage(maxPixelWidth: 480, maxPixelHeight: 480),
          let png = encodePNG(image) else { return nil }
    return ScrollingPreview(pngData: png, width: matcher.pixelWidth, height: matcher.outputHeight, notice: notice)
  }

  private func cgImage(_ viewport: ScrollingViewport) -> CGImage? {
    let pixels = [UInt8](viewport.pixels)
    let data = Data(pixels) as CFData
    guard let provider = CGDataProvider(data: data) else { return nil }
    return CGImage(width: viewport.width, height: viewport.height, bitsPerComponent: 8, bitsPerPixel: 32,
                   bytesPerRow: viewport.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
  }

  private func encodePNG(_ image: CGImage) -> Data? {
    let bytes = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return bytes as Data
  }
}
