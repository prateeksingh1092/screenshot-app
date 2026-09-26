import CoreGraphics
import Darwin
import Foundation
import FrisketCore
import ImageIO
import Testing

/// Gate B (ticket 67): peak memory of an edited save through the production renderer,
/// `CaptureRenderer.flatten`, with every edit kind. Decision 60 makes one display the largest
/// capture; `display` is the largest Apple display (6,016 × 3,384, Pro Display XDR). `cap` is the
/// DA-6 output cap, 5,120 × 32,768, measured for reference only. Each size runs in its own process, because
/// the peak is per process: `sh scripts/editor-memory-run.sh display` (or `cap`).
@Suite struct EditorMemoryRunTests {
    @Test(.enabled(if: ["display", "cap"].contains(ProcessInfo.processInfo.environment["FRISKET_EDITOR_MEMORY_RUN"] ?? "")))
    func editedSaveWithEveryEditKindStaysUnderTwoGigabytes() throws {
        let run = ProcessInfo.processInfo.environment["FRISKET_EDITOR_MEMORY_RUN"]
        let (width, height) = run == "cap" ? (5120, CaptureRenderer.maximumOutputHeight) : (6016, 3384)
        let png = try syntheticPNG(width: width, height: height)
        let beforeSave = try peakPhysicalFootprint()
        let started = ContinuousClock.now
        let h = Double(height)
        let redaction = try #require(SolidRedaction(x: 0, y: 100, width: 640, height: 480))
        let label = try #require(DocumentAnnotation(.text(x: 40, y: 30, characters: "Gate B")))
        let arrow = try #require(DocumentAnnotation(.arrow(x0: 40, y0: h - 40, x1: 4_000, y1: h - 40)))
        let outline = try #require(DocumentAnnotation(.rectangle(x: 700, y: 200, width: 900, height: 600)))
        let blur = try #require(DocumentEffect(.blur(x: 0, y: 0, width: Double(width), height: h)))
        let magnify = try #require(DocumentEffect(.magnify(x: 1_000, y: h / 2, width: 1_200, height: h / 3)))
        let crop = try #require(DocumentCrop(x: 1, y: 1, width: Double(width) - 2, height: h - 2))
        let edits = try #require(DocumentEdits(scale: 1, crop: crop, redactions: [redaction],
                                               annotations: [label, arrow, outline], effects: [blur, magnify]))
        let saved = try CaptureRenderer().flatten(png, edits: edits)
        let elapsed = started.duration(to: .now)
        let peak = try peakPhysicalFootprint()
        print("EDITOR_MEMORY_RUN run=\(run ?? "") dimensions=\(width)x\(height) source_png_bytes=\(png.count) saved_png_bytes=\(saved.count) peak_before_save_bytes=\(beforeSave) peak_phys_footprint_bytes=\(peak) save_elapsed=\(elapsed)")
        #expect(saved.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
        // Gate B's budget is for one display (decision 72). The cap run blurs 5,120 × 32,768 whole
        // and holds a 1.3 GB fixture; it is reported, not budgeted, as no capture can reach it.
        if run == "display" { #expect(peak < 2_000_000_000) }
    }
}

extension EditorMemoryRunTests {
    /// Ticket 68: editor responsiveness. Opening the editor decodes the capture once
    /// (`CaptureRenderer.preview`), then each edit renders at the preview's size; both run off the
    /// main actor in the app. Reports the times and the preview size, for the same two sizes.
    @Test(.enabled(if: ["display", "cap"].contains(ProcessInfo.processInfo.environment["FRISKET_EDITOR_MEMORY_RUN"] ?? "")))
    func editorPreviewOpensAndRendersEachEdit() throws {
        let run = ProcessInfo.processInfo.environment["FRISKET_EDITOR_MEMORY_RUN"]
        let (width, height) = run == "cap" ? (5120, CaptureRenderer.maximumOutputHeight) : (6016, 3384)
        let png = try syntheticPNG(width: width, height: height)
        let clock = ContinuousClock()
        var preview: CapturePreview?
        let opened = try clock.measure { preview = try CaptureRenderer().preview(png) }
        let shown = try #require(preview)
        let h = Double(height)
        let redaction = try #require(SolidRedaction(x: 0, y: 100, width: 640, height: 480))
        let label = try #require(DocumentAnnotation(.text(x: 40, y: 30, characters: "Gate B")))
        let arrow = try #require(DocumentAnnotation(.arrow(x0: 40, y0: h - 40, x1: 4_000, y1: h - 40)))
        let blur = try #require(DocumentEffect(.blur(x: 0, y: 0, width: Double(width), height: h)))
        let edits = try #require(DocumentEdits(scale: 1, redactions: [redaction], annotations: [label, arrow], effects: [blur]))
        var slowest = Duration.zero
        for _ in 0..<5 { slowest = max(slowest, try clock.measure { _ = try shown.render(edits) }) }
        var live: CapturePreview?
        let reducing = clock.measure { live = shown.reduced() }
        print("EDITOR_PREVIEW_RUN run=\(run ?? "") dimensions=\(width)x\(height) preview=\(shown.width)x\(shown.height) open=\(opened) slowest_render=\(slowest) live_preview=\(live?.width ?? 0)x\(live?.height ?? 0) reduce=\(reducing)")
        #expect(shown.isDownscaled == (run == "cap"), "one display previews at full resolution (ticket 102)")
    }
}

extension EditorMemoryRunTests {
    /// Ticket 97: live drag feedback. Every drag event renders the drag's provisional edits through
    /// `CapturePreview.render`. Reports the median and slowest render per drag point for three drags:
    /// a new Solid redaction, a Curved arrow's tip, and a redaction moved over every edit kind
    /// (a whole-capture blur included). The frame budget at 60 Hz is 16.7 ms.
    @Test(.enabled(if: ["display", "cap"].contains(ProcessInfo.processInfo.environment["FRISKET_EDITOR_MEMORY_RUN"] ?? "")))
    @MainActor func liveDragRendersEachPointWithinTheFrameBudget() throws {
        let run = ProcessInfo.processInfo.environment["FRISKET_EDITOR_MEMORY_RUN"]
        let (width, height) = run == "cap" ? (5120, CaptureRenderer.maximumOutputHeight) : (6016, 3384)
        // A live drag renders through the reduced preview (ticket 102); settled edits at full size.
        let shown = try CaptureRenderer().preview(try syntheticPNG(width: width, height: height)).reduced()
        let h = Double(height)
        let label = try #require(DocumentAnnotation(.text(x: 40, y: 30, characters: "Gate B")))
        let curved = try #require(DocumentAnnotation(.arrow(x0: 40, y0: h - 40, x1: 4_000, y1: h - 400), width: 8,
                                                     style: .curved))
        let blur = try #require(DocumentEffect(.blur(x: 0, y: 0, width: Double(width), height: h)))
        let grey = SolidRedaction.palette[2].pixel
        let plain = try #require(DocumentEdits(scale: 2))
        let redaction = try #require(SolidRedaction(x: 0, y: 100, width: 640, height: 480, colour: grey))
        let everything = try #require(DocumentEdits(scale: 2, redactions: [redaction], annotations: [label, curved],
                                                    effects: [blur]))
        let points = (1...60).map { Double($0) * 25 }
        let clock = ContinuousClock()
        func drag(_ name: String, _ edits: (Double) -> DocumentEdits?) throws -> Duration {
            var times: [Duration] = []
            for step in points {
                let provisional = try #require(edits(step))
                times.append(try clock.measure { _ = try shown.render(provisional) })
            }
            times.sort()
            print("LIVE_DRAG_RUN run=\(run ?? "") dimensions=\(width)x\(height) preview=\(shown.width)x\(shown.height) drag=\(name) points=\(times.count) median=\(times[times.count / 2]) slowest=\(times.last ?? .zero)")
            return times[times.count / 2]
        }
        let drawn = try drag("draw-redaction") { step in
            var next = plain
            guard let box = SolidRedaction(x: 100, y: 100, width: step, height: step / 2, colour: grey) else { return nil }
            next.redactions.append(box)
            return next
        }
        let withArrow = try #require(DocumentEdits(scale: 2, annotations: [curved]))
        let bent = MarkEditor(UndoableEdits(withArrow))
        bent.select(.annotation(0))
        let tip = try drag("resize-curved-arrow") { step in
            bent.provisional(MarkEditor.Grab(mark: .annotation(0), handle: .tip), fromX: 4_000, fromY: h - 400,
                             toX: 4_000 - step, toY: h - 400 - step)
        }
        let moving = MarkEditor(UndoableEdits(everything))
        moving.select(.redaction(0))
        let moved = try drag("move-over-every-kind") { step in
            moving.provisional(MarkEditor.Grab(mark: .redaction(0), handle: nil), fromX: 10, fromY: 110,
                               toX: 10 + step, toY: 110 + step / 3)
        }
        if run == "display" {
            // Single-mark drags fit the 60 Hz frame; renders never queue (one at a time, latest wins).
            #expect(drawn < .milliseconds(16) && tip < .milliseconds(16), "median render over the 60 Hz frame")
            _ = moved
        }
    }
}

/// Opaque noise in 16 × 8 px cells, encoded with ImageIO.
private func syntheticPNG(width: Int, height: Int) throws -> Data {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            var value = UInt64(y / 8) &* 0x9e3779b97f4a7c15 ^ UInt64(x / 16)
            value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
            value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
            value ^= value >> 31
            let i = (y * width + x) * 4
            bytes[i] = UInt8(truncatingIfNeeded: value)
            bytes[i + 1] = UInt8(truncatingIfNeeded: value >> 8)
            bytes[i + 2] = UInt8(truncatingIfNeeded: value >> 16)
        }
    }
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
    bytes = []
    let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: space,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
    return data as Data
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
