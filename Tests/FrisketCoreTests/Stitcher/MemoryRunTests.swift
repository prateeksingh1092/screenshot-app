import CoreGraphics
import Darwin
import Foundation
import Testing
import FrisketCore

struct MemoryRunTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["FRISKET_MEMORY_RUN"] == "1"))
  func fullSizeCaptureFitsPhysicalFootprintBudget() throws {
    let started = ContinuousClock.now
    let width = 5120, frameHeight = 1440, step = 720, finalHeight = 57_600
    var generationFailure: Error?
    let frames = stride(from: 0, through: finalHeight - frameHeight, by: step).lazy.compactMap { offset -> ScrollingCaptureFrame? in
      do {
        return ScrollingCaptureFrame(image: try syntheticFrame(width: width, height: frameHeight, offset: offset),
          expectedVerticalStep: step)
      } catch { generationFailure = error; return nil }
    }
    let capture = try Stitcher.stitch(frames)
    if let generationFailure { throw generationFailure }
    #expect(capture.alignments.count == 79)
    #expect(capture.alignments.dropFirst().allSatisfy { $0.disposition == .appended && $0.appendedRows == step })
    let visionEstimates = capture.alignments.filter(\.usedVisionEstimate).count
    // Exercise the public image, including a consumer that requests all its bytes.
    let image = capture.image
    #expect(image.width == width)
    #expect(image.height == finalHeight)
    let data = try #require(image.dataProvider?.data)
    #expect(CFDataGetLength(data) == 1_179_648_000)
    let actual = try #require(CFDataGetBytePtr(data))
    var row = 0, strips = 0
    for _ in 0..<225 {
      try autoreleasepool {
        let reference = try syntheticFrame(width: width, height: 256, offset: row)
        let expected = try #require(reference.dataProvider?.data)
        #expect(memcmp(actual.advanced(by: row * width * 4), CFDataGetBytePtr(expected), CFDataGetLength(expected)) == 0,
          "Full-image rows starting at \(row)")
        row += 256
        strips += 1
      }
    }
    #expect(row == finalHeight)
    #expect(strips == 225)
    // The kernel maintains this high-water ledger; no sampling can miss a spike.
    let peak = try peakPhysicalFootprint()
    print("MEMORY_RUN dimensions=5120x57600 frames=79 validated_chunks=\(strips) bytes=1179648000 peak_phys_footprint_bytes=\(peak) elapsed=\(started.duration(to: .now)) vision_estimates=\(visionEstimates)")
    #expect(peak < 2_000_000_000)
    withExtendedLifetime(data) {}
  }

  private func peakPhysicalFootprint() throws -> Int64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    try #require(result == KERN_SUCCESS)
    // rev3 introduced the peak field. Never silently report an unavailable zero.
    let peakEnd = try #require(MemoryLayout<task_vm_info_data_t>.offset(of: \.ledger_phys_footprint_peak)) + MemoryLayout<Int64>.size
    try #require(Int(count) * MemoryLayout<integer_t>.size >= peakEnd)
    try #require(info.ledger_phys_footprint_peak > 0)
    return info.ledger_phys_footprint_peak
  }

  private func syntheticFrame(width: Int, height: Int, offset: Int) throws -> CGImage {
    var data = Data(count: width * height * 4)
    data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
      let pixels = buffer.bindMemory(to: UInt8.self)
      for y in 0..<height {
        // A deterministic synthetic document: nonperiodic coloured 8x16 cells.
        // Coordinates refer to the whole document; only one viewport is allocated.
        for x in 0..<width {
          var value = UInt64((y + offset) / 8) &* 0x9e3779b97f4a7c15 ^ UInt64(x / 16)
          value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
          value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
          value ^= value >> 31
          let i = (y * width + x) * 4
          pixels[i] = UInt8(truncatingIfNeeded: value)
          pixels[i + 1] = UInt8(truncatingIfNeeded: value >> 8)
          pixels[i + 2] = UInt8(truncatingIfNeeded: value >> 16)
          pixels[i + 3] = 255
        }
      }
    }
    let provider = try #require(CGDataProvider(data: data as CFData))
    return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
  }
}
