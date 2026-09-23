import CoreGraphics
import Darwin
import Foundation
import FrisketCore
import Testing

struct ScrollingSessionMemoryTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FRISKET_SCROLL_MEMORY"] == "1"))
    func scrollingSessionFitsTheTrialMemoryGate() throws {
        let session = ScrollingCaptureSession(budget: .v1)
        let width = 1920
        let height = 1080
        let step = 360
        for offset in stride(from: 0, through: step * 7, by: step) {
            let image = try #require(TestImageFactory.repeatedScrollingFrame(width: width, height: height, logicalYOffset: offset))
            let viewport = try #require(ScrollingViewport(cgImage: image))
            _ = session.ingest(viewport)
        }
        let png = try #require(session.finish()?.pngData)
        #expect(!png.isEmpty)
        let peak = try peakPhysicalFootprint()
        print("SCROLL_SESSION frames=8 viewport=1920x1080 step=360 png_bytes=\(png.count) peak_phys_footprint_bytes=\(peak)")
        #expect(peak > 0)
        #expect(peak < 2_000_000_000)
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
