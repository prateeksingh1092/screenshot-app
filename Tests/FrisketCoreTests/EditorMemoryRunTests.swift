import Darwin
import Foundation
import FrisketCore
import Testing

@Suite struct EditorMemoryRunTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FRISKET_EDITOR_MEMORY_RUN"] == "1"))
    func tallSyntheticEditStaysUnderTwoGigabytes() throws {
        let started = ContinuousClock.now
        let width = 5120, height = CaptureRenderer.maximumOutputHeight
        let redaction = try #require(SolidRedaction(x: 0, y: 1000, width: 64, height: 64))
        let edits = try #require(DocumentEdits(scale: 1, redactions: [redaction]))
        let encoder = try #require(StripPNGEncoder(width: width, height: height))
        var strips = 0
        DocumentRenderer.forEachStrip(width: width, height: height, edits: edits) { start, count in
            syntheticRows(width: width, start: start, count: count)
        } body: { strip in
            #expect(encoder.append(strip))
            strips += 1
        }
        let png = try #require(encoder.finish())
        #expect(strips == 128)
        #expect(png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
        let peak = try peakPhysicalFootprint()
        print("EDITOR_MEMORY_RUN dimensions=5120x\(height) strips=\(strips) png_bytes=\(png.count) peak_phys_footprint_bytes=\(peak) elapsed=\(started.duration(to: .now))")
        #expect(peak < 2_000_000_000)
        withExtendedLifetime(png) {}
    }
}

private func syntheticRows(width: Int, start: Int, count: Int) -> Bitmap? {
    var bytes = [UInt8](repeating: 255, count: width * count * 4)
    for y in 0..<count {
        let documentY = start + y
        for x in 0..<width {
            var value = UInt64(documentY / 8) &* 0x9e3779b97f4a7c15 ^ UInt64(x / 16)
            value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
            value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
            value ^= value >> 31
            let i = (y * width + x) * 4
            bytes[i] = UInt8(truncatingIfNeeded: value)
            bytes[i + 1] = UInt8(truncatingIfNeeded: value >> 8)
            bytes[i + 2] = UInt8(truncatingIfNeeded: value >> 16)
            bytes[i + 3] = 255
        }
    }
    return Bitmap(width: width, height: count, bytes: bytes)
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
