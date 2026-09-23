import CoreGraphics
import Foundation
import Testing
import Vision
@testable import StitcherTrial

struct VisionProbeTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["FRISKET_VISION_PROBE"] == "1"))
  func visionAssistedAlignmentProbe() throws {
    let first = try #require(probeFrame(offset: 0))
    let next = try #require(probeFrame(offset: 80))
    let request = VNTranslationalImageRegistrationRequest(targetedCGImage: next)
    do {
      try VNSequenceRequestHandler().perform([request], on: first)
    } catch {
      let error = error as NSError
      print("VISION_PROBE failure domain=\(error.domain) code=\(error.code) description=\(error.localizedDescription)")
      throw error
    }
    let observation = try #require(request.results?.first as? VNImageTranslationAlignmentObservation)
    print("VISION_PROBE translation tx=\(observation.alignmentTransform.tx) ty=\(observation.alignmentTransform.ty)")
    #expect(abs(observation.alignmentTransform.tx) < 2)
    #expect(abs(abs(observation.alignmentTransform.ty) - 80) < 2)
    let stitcher = ScrollingCaptureStitcher()
    _ = try #require(stitcher.start(with: first))
    let update = try #require(stitcher.append(next, maxOutputHeight: 2000, expectedSignedDeltaPixels: 80))
    #expect(update.alignmentDebug?.usedVisionEstimate == true)
    #expect(update.alignmentDebug?.appendDeltaY == 80)
    #expect(update.outputHeight == 480)
    print("VISION_PROBE stitcher usedVisionEstimate=\(update.alignmentDebug?.usedVisionEstimate == true) height=\(update.outputHeight)")
  }

  private func probeFrame(offset: Int) -> CGImage? {
    let width = 320, height = 400
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        // Stable 2D texture with blocks large enough for registration's downsampling.
        var value = UInt64((y + offset) / 4) &* 0x9e3779b97f4a7c15 ^ UInt64(x / 4)
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        let gray = UInt8(truncatingIfNeeded: value ^ (value >> 31))
        let i = (y * width + x) * 4
        bytes[i] = gray; bytes[i + 1] = gray; bytes[i + 2] = gray
      }
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
  }
}
