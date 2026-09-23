import CoreGraphics
import Darwin
import Foundation
import FrisketCore
import ImageIO
import Testing

struct ScrollingSessionMemoryTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FRISKET_SCROLL_MEMORY"] == "1"))
    func scrollingSessionFitsTheTrialMemoryGate() throws {
        let session = ScrollingCaptureSession(budget: .v1)
        let width = 1920
        let height = 1080
        let step = 360
        for offset in stride(from: 0, through: step * 7, by: step) {
            let image = try syntheticDocument(width: width, height: height, offset: offset)
            let viewport = try #require(ScrollingViewport(cgImage: image))
            let result = session.ingest(viewport)
            guard case let .preview(preview) = result else {
                Issue.record("Expected accepted viewport at offset \(offset), got \(result)")
                return
            }
            try #require(preview.width == width)
            try #require(preview.height == height + offset)
        }
        let png = try #require(session.finish()?.pngData)
        #expect(!png.isEmpty)
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        try #require(decoded.width == 1920)
        try #require(decoded.height == 3600)
        let reference = try syntheticDocument(width: 1920, height: 3600, offset: 0)
        let actual = try #require(decoded.dataProvider?.data)
        #expect(actual as Data == reference.dataProvider?.data as Data?)
        let peak = try peakPhysicalFootprint()
        print("SCROLL_SESSION frames=8 viewport=1920x1080 step=360 output=1920x3600 verified_bytes=27648000 png_bytes=\(png.count) peak_phys_footprint_bytes=\(peak)")
        #expect(peak > 0)
        #expect(peak < 2_000_000_000)
    }

    // Nonperiodic document cells, as in the full-size stitcher memory fixture.
    // Wide repeated bands are ambiguous without a scroll hint; a memory success
    // fixture must establish alignment as well as measure allocations.
    private func syntheticDocument(width: Int, height: Int, offset: Int) throws -> CGImage {
        var data = Data(count: width * height * 4)
        data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            let pixels = buffer.bindMemory(to: UInt8.self)
            for y in 0..<height {
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

    private func peakPhysicalFootprint() throws -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        try #require(result == KERN_SUCCESS)
        let peakEnd = try #require(MemoryLayout<task_vm_info_data_t>.offset(of: \.ledger_phys_footprint_peak)) + MemoryLayout<Int64>.size
        try #require(Int(count) * MemoryLayout<integer_t>.size >= peakEnd)
        try #require(info.ledger_phys_footprint_peak > 0)
        return info.ledger_phys_footprint_peak
    }
}
