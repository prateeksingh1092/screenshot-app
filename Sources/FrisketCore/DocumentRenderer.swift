import Accelerate
import CoreGraphics
import Foundation

/// A pure function from document to bitmap; the same document always renders the same pixels.
///
/// Crop is applied first, snapped outward to whole output pixels. Each Solid redaction is then
/// scaled to output pixels, snapped outward (down on the minimum edges, up on the maximum
/// edges), shifted by the crop's whole-pixel origin, clipped to the cropped image, and copied
/// as opaque fill with no blending or antialiasing. Every mark therefore covers the same
/// content it would cover without the crop (D18). Blur (vImage) and Magnify (CoreGraphics) then read only
/// that redacted composite, inside their own box; redactions are stamped again afterwards. Annotations
/// draw last, natively (`AnnotationPainter`): a white plate, the redactions once more, then ink.
public enum DocumentRenderer {
    public static let stripHeight = 256
    /// One output pixel of white around annotation ink. It is a constant, never a sample of the capture.
    public static let plate = RGBAPixel(red: 255, green: 255, blue: 255, alpha: 255)

    public static func render(_ document: EditorDocument) -> Bitmap {
        var output = croppedBase(document.base, crop: document.edits.crop, scale: document.edits.scale)
        let origin = cropOrigin(width: document.base.width, height: document.base.height,
                                crop: document.edits.crop, scale: document.edits.scale)
        paint(&output, edits: document.edits, origin: origin, rowShift: 0,
              fullWidth: output.width, fullHeight: output.height)
        return output
    }

    /// Yields top-to-bottom output strips without retaining the full rendered bitmap.
    public static func forEachStrip(_ document: EditorDocument, stripHeight: Int = stripHeight,
                                    body: (Bitmap) throws -> Void) rethrows {
        try forEachStrip(width: document.base.width, height: document.base.height, edits: document.edits,
                         stripHeight: stripHeight, copyRows: { start, count in
            croppedRows(document.base, crop: document.edits.crop, scale: document.edits.scale,
                        startRow: start, rowCount: count)
        }, body: body)
    }

    /// Same strip walk when the base is produced a few rows at a time.
    public static func forEachStrip(width: Int, height: Int, edits: DocumentEdits,
                                    stripHeight: Int = stripHeight,
                                    copyRows: (Int, Int) -> Bitmap?,
                                    body: (Bitmap) throws -> Void) rethrows {
        let size = cropBounds(width: width, height: height, crop: edits.crop, scale: edits.scale)
        let origin = cropOrigin(width: width, height: height, crop: edits.crop, scale: edits.scale)
        let rowsPerStrip = max(1, stripHeight)
        var row = 0
        while row < size.height {
            let count = min(rowsPerStrip, size.height - row)
            try body(renderWindow(edits: edits, origin: origin, startRow: row, rowCount: count, full: size,
                                  copyRows: copyRows))
            row += count
        }
    }

    public static func concatenate(_ strips: [Bitmap]) -> Bitmap? {
        guard let first = strips.first, strips.allSatisfy({ $0.width == first.width }) else { return nil }
        let height = strips.reduce(0) { $0 + $1.height }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(first.width * height * 4)
        for strip in strips { bytes.append(contentsOf: strip.bytes) }
        return Bitmap(width: first.width, height: height, bytes: bytes)
    }

    public static func outputSize(_ document: EditorDocument) -> (width: Int, height: Int) {
        outputSize(width: document.base.width, height: document.base.height, edits: document.edits)
    }

    public static func outputSize(width: Int, height: Int, edits: DocumentEdits) -> (width: Int, height: Int) {
        cropBounds(width: width, height: height, crop: edits.crop, scale: edits.scale)
    }

    private static func renderWindow(edits: DocumentEdits, origin: (x: Int, y: Int), startRow: Int, rowCount: Int,
                                     full: (width: Int, height: Int),
                                     copyRows: (Int, Int) -> Bitmap?) -> Bitmap {
        let rows = windowRows(edits: edits, origin: origin, startRow: startRow, rowCount: rowCount, full: full)
        let paddedStart = rows.lowerBound, paddedEnd = rows.upperBound
        var window = copyRows(paddedStart, paddedEnd - paddedStart)
            ?? Bitmap(width: full.width, height: rowCount, bytes: [UInt8](repeating: 0, count: full.width * rowCount * 4))!
        paint(&window, edits: edits, origin: origin, rowShift: paddedStart, fullWidth: full.width, fullHeight: full.height)
        guard paddedStart != startRow || paddedEnd != startRow + rowCount else { return window }
        let localStart = startRow - paddedStart
        var bytes: [UInt8] = []
        bytes.reserveCapacity(window.width * rowCount * 4)
        for y in localStart..<(localStart + rowCount) {
            let start = y * window.width * 4
            bytes.append(contentsOf: window.bytes[start..<(start + window.width * 4)])
        }
        return Bitmap(width: window.width, height: rowCount, bytes: bytes) ?? window
    }

    /// The strip's rows, widened to the whole rows of every effect box they meet (and of any box
    /// those rows then meet), so each effect reads exactly the pixels it reads in the whole image.
    private static func windowRows(edits: DocumentEdits, origin: (x: Int, y: Int), startRow: Int, rowCount: Int,
                                   full: (width: Int, height: Int)) -> Range<Int> {
        let spans = edits.effects.compactMap { effect -> Range<Int>? in
            let r = effect.rectangle
            return snapped(x: r.x, y: r.y, width: r.width, height: r.height, scale: edits.scale,
                           originX: origin.x, originY: origin.y, rowShift: 0,
                           fullWidth: full.width, fullHeight: full.height, outputHeight: full.height)
                .map { $0.minY..<$0.maxY }
        }
        var lower = startRow, upper = startRow + rowCount
        var widened = true
        while widened {
            widened = false
            for span in spans where span.overlaps(lower..<upper) && (span.lowerBound < lower || span.upperBound > upper) {
                lower = min(lower, span.lowerBound)
                upper = max(upper, span.upperBound)
                widened = true
            }
        }
        return lower..<upper
    }

    /// The crop's snapped top-left in output pixels of the uncropped image, for a capture of this size.
    static func cropOrigin(width: Int, height: Int, edits: DocumentEdits) -> (x: Int, y: Int) {
        cropOrigin(width: width, height: height, crop: edits.crop, scale: edits.scale)
    }

    /// Paints redactions, effects, redactions again, then annotations over an already cropped
    /// output. `CaptureRenderer` uses it so the delivered image matches the preview's `render`.
    static func paintEdits(_ output: inout Bitmap, edits: DocumentEdits, origin: (x: Int, y: Int)) {
        paint(&output, edits: edits, origin: origin, rowShift: 0, fullWidth: output.width, fullHeight: output.height)
    }

    /// `origin` is the crop's top-left in output pixels of the uncropped image, already snapped.
    private static func paint(_ output: inout Bitmap, edits: DocumentEdits, origin: (x: Int, y: Int), rowShift: Int,
                              fullWidth: Int, fullHeight: Int) {
        let scale = edits.scale
        let originX = origin.x
        let originY = origin.y
        fillRedactions(edits.redactions, on: &output, scale: scale, originX: originX, originY: originY,
                       rowShift: rowShift, fullWidth: fullWidth, fullHeight: fullHeight)
        for effect in edits.effects {
            apply(effect, on: &output, scale: scale, originX: originX, originY: originY,
                  rowShift: rowShift, fullWidth: fullWidth, fullHeight: fullHeight)
        }
        fillRedactions(edits.redactions, on: &output, scale: scale, originX: originX, originY: originY,
                       rowShift: rowShift, fullWidth: fullWidth, fullHeight: fullHeight)
        // Plates first, then the redactions again so no plate pixel lands on a redacted pixel,
        // then ink above everything (annotations draw above Solid redactions).
        guard !edits.annotations.isEmpty else { return }
        AnnotationPainter.draw(edits.annotations, layer: .plate, on: &output, scale: scale, origin: origin,
                               rowShift: rowShift, fullWidth: fullWidth, fullHeight: fullHeight)
        fillRedactions(edits.redactions, on: &output, scale: scale, originX: originX, originY: originY,
                       rowShift: rowShift, fullWidth: fullWidth, fullHeight: fullHeight)
        AnnotationPainter.draw(edits.annotations, layer: .ink, on: &output, scale: scale, origin: origin,
                               rowShift: rowShift, fullWidth: fullWidth, fullHeight: fullHeight)
    }

    private static func fillRedactions(_ redactions: [SolidRedaction], on output: inout Bitmap, scale: Double,
                                       originX: Int, originY: Int,
                                       rowShift: Int, fullWidth: Int, fullHeight: Int) {
        let boxes = redactions.compactMap { redaction in
            snapped(x: redaction.x, y: redaction.y, width: redaction.width, height: redaction.height,
                    scale: scale, originX: originX, originY: originY, rowShift: rowShift,
                    fullWidth: fullWidth, fullHeight: fullHeight, outputHeight: output.height).map { (box: $0, fill: redaction.colour) }
        }
        let rowWidth = output.width
        output.bytes.withUnsafeMutableBytes { raw in
            guard let pixels = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for (bounds, fill) in boxes {
                let span = bounds.maxX - bounds.minX
                for y in bounds.minY..<bounds.maxY {
                    var index = (y * rowWidth + bounds.minX) * 4
                    for _ in 0..<span {
                        pixels[index] = fill.red
                        pixels[index + 1] = fill.green
                        pixels[index + 2] = fill.blue
                        pixels[index + 3] = fill.alpha
                        index += 4
                    }
                }
            }
        }
    }

    private static func apply(_ effect: DocumentEffect, on output: inout Bitmap, scale: Double,
                              originX: Int, originY: Int, rowShift: Int, fullWidth: Int, fullHeight: Int) {
        let r = effect.rectangle
        guard let bounds = snapped(x: r.x, y: r.y, width: r.width, height: r.height,
                                   scale: scale, originX: originX, originY: originY, rowShift: rowShift,
                                   fullWidth: fullWidth, fullHeight: fullHeight, outputHeight: output.height) else { return }
        // Each effect copies its box out, works on that copy alone and writes it back, so it never
        // reads a pixel outside its box, and it runs after the redactions are stamped.
        var box = copyBox(bounds, from: output)
        let width = bounds.maxX - bounds.minX, height = bounds.maxY - bounds.minY
        switch effect.kind {
        case .blur: blur(&box, width: width, height: height)
        case .magnify: magnify(&box, width: width, height: height)
        }
        writeBox(box, bounds, to: &output)
    }

    /// Blur passes: the same 3×3 box average, repeated.
    static let blurPasses = 6

    /// vImage box convolution, edge-extended at the box's edges (deterministic on x86_64 and arm64).
    /// Averaging premultiplied RGBA keeps every channel at or under its alpha.
    private static func blur(_ box: inout [UInt8], width: Int, height: Int) {
        var scratch = [UInt8](repeating: 0, count: box.count)
        box.withUnsafeMutableBytes { boxRaw in
            scratch.withUnsafeMutableBytes { scratchRaw in
                var source = vImage_Buffer(data: boxRaw.baseAddress, height: vImagePixelCount(height),
                                           width: vImagePixelCount(width), rowBytes: width * 4)
                var destination = vImage_Buffer(data: scratchRaw.baseAddress, height: vImagePixelCount(height),
                                                width: vImagePixelCount(width), rowBytes: width * 4)
                for _ in 0..<blurPasses {
                    vImageBoxConvolve_ARGB8888(&source, &destination, nil, 0, 0, 3, 3, nil,
                                               vImage_Flags(kvImageEdgeExtend))
                    swap(&source, &destination)
                }
                if source.data != boxRaw.baseAddress {
                    boxRaw.baseAddress!.copyMemory(from: source.data, byteCount: boxRaw.count)
                }
            }
        }
    }

    /// CoreGraphics draws the box's top-left quarter at twice the size over the whole box, with no
    /// interpolation, so each source pixel becomes a 2×2 block.
    private static func magnify(_ box: inout [UInt8], width: Int, height: Int) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(box) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let quarter = image.cropping(to: CGRect(x: 0, y: 0, width: (width + 1) / 2, height: (height + 1) / 2))
        else { return }
        box.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.setShouldAntialias(false)
            // Device space is bottom-up: the enlarged quarter's top edge sits on the box's top edge.
            let drawn = (width: quarter.width * 2, height: quarter.height * 2)
            context.draw(quarter, in: CGRect(x: 0, y: height - drawn.height, width: drawn.width, height: drawn.height))
            context.flush()
        }
    }

    private static func copyBox(_ bounds: (minX: Int, minY: Int, maxX: Int, maxY: Int), from output: Bitmap) -> [UInt8] {
        let rowBytes = (bounds.maxX - bounds.minX) * 4
        var box = [UInt8](repeating: 0, count: rowBytes * (bounds.maxY - bounds.minY))
        output.bytes.withUnsafeBytes { pixels in
            box.withUnsafeMutableBytes { copy in
                for row in 0..<(bounds.maxY - bounds.minY) {
                    let from = ((bounds.minY + row) * output.width + bounds.minX) * 4
                    (copy.baseAddress! + row * rowBytes).copyMemory(from: pixels.baseAddress! + from, byteCount: rowBytes)
                }
            }
        }
        return box
    }

    private static func writeBox(_ box: [UInt8], _ bounds: (minX: Int, minY: Int, maxX: Int, maxY: Int),
                                 to output: inout Bitmap) {
        let rowBytes = (bounds.maxX - bounds.minX) * 4
        let outputWidth = output.width
        output.bytes.withUnsafeMutableBytes { pixels in
            box.withUnsafeBytes { copy in
                for row in 0..<(bounds.maxY - bounds.minY) {
                    let to = ((bounds.minY + row) * outputWidth + bounds.minX) * 4
                    (pixels.baseAddress! + to).copyMemory(from: copy.baseAddress! + row * rowBytes, byteCount: rowBytes)
                }
            }
        }
    }

    private static func snapped(x: Double, y: Double, width: Double, height: Double, scale: Double,
                                originX: Int, originY: Int, rowShift: Int,
                                fullWidth: Int, fullHeight: Int, outputHeight: Int)
    -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        func column(_ value: Double) -> Int { Int(min(max(value, 0), Double(fullWidth))) }
        func row(_ value: Double) -> Int { Int(min(max(value, 0), Double(fullHeight))) }
        let minX = column((x * scale).rounded(.down) - Double(originX))
        let rawMinY = row((y * scale).rounded(.down) - Double(originY))
        let maxX = column(((x + width) * scale).rounded(.up) - Double(originX))
        let rawMaxY = row(((y + height) * scale).rounded(.up) - Double(originY))
        let minY = max(0, rawMinY - rowShift)
        let maxY = min(outputHeight, rawMaxY - rowShift)
        return minX < maxX && minY < maxY ? (minX, minY, maxX, maxY) : nil
    }

    private static func cropBounds(_ base: Bitmap, crop: DocumentCrop?, scale: Double) -> (width: Int, height: Int) {
        cropBounds(width: base.width, height: base.height, crop: crop, scale: scale)
    }

    private static func cropBounds(width: Int, height: Int, crop: DocumentCrop?, scale: Double) -> (width: Int, height: Int) {
        guard let crop else { return (width, height) }
        func column(_ value: Double) -> Int { Int(min(max(value, 0), Double(width))) }
        func row(_ value: Double) -> Int { Int(min(max(value, 0), Double(height))) }
        let minX = column((crop.x * scale).rounded(.down))
        let minY = row((crop.y * scale).rounded(.down))
        let maxX = column(((crop.x + crop.width) * scale).rounded(.up))
        let maxY = row(((crop.y + crop.height) * scale).rounded(.up))
        return minX < maxX && minY < maxY ? (maxX - minX, maxY - minY) : (width, height)
    }

    /// The crop's snapped top-left in output pixels of the uncropped image; the same pixel `croppedRows` starts at.
    private static func cropOrigin(width: Int, height: Int, crop: DocumentCrop?, scale: Double) -> (x: Int, y: Int) {
        guard let crop else { return (0, 0) }
        func column(_ value: Double) -> Int { Int(min(max(value, 0), Double(width))) }
        func row(_ value: Double) -> Int { Int(min(max(value, 0), Double(height))) }
        return (column((crop.x * scale).rounded(.down)), row((crop.y * scale).rounded(.down)))
    }

    private static func croppedBase(_ base: Bitmap, crop: DocumentCrop?, scale: Double) -> Bitmap {
        croppedRows(base, crop: crop, scale: scale, startRow: 0, rowCount: cropBounds(base, crop: crop, scale: scale).height) ?? base
    }

    private static func croppedRows(_ base: Bitmap, crop: DocumentCrop?, scale: Double,
                                    startRow: Int, rowCount: Int) -> Bitmap? {
        let bounds = cropBounds(base, crop: crop, scale: scale)
        guard startRow >= 0, rowCount > 0, startRow + rowCount <= bounds.height else { return nil }
        guard let crop else {
            var bytes: [UInt8] = []
            bytes.reserveCapacity(base.width * rowCount * 4)
            let start = startRow * base.width * 4
            bytes.append(contentsOf: base.bytes[start..<(start + base.width * rowCount * 4)])
            return Bitmap(width: base.width, height: rowCount, bytes: bytes)
        }
        func column(_ value: Double) -> Int { Int(min(max(value, 0), Double(base.width))) }
        func row(_ value: Double) -> Int { Int(min(max(value, 0), Double(base.height))) }
        let minX = column((crop.x * scale).rounded(.down))
        let minY = row((crop.y * scale).rounded(.down))
        let width = bounds.width
        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * rowCount * 4)
        for y in (minY + startRow)..<(minY + startRow + rowCount) {
            let start = (y * base.width + minX) * 4
            bytes.append(contentsOf: base.bytes[start..<(start + width * 4)])
        }
        return Bitmap(width: width, height: rowCount, bytes: bytes)
    }
}

extension DocumentEffect {
    /// The effect's box in document points.
    var rectangle: (x: Double, y: Double, width: Double, height: Double) {
        switch kind {
        case let .blur(x, y, width, height), let .magnify(x, y, width, height): (x, y, width, height)
        }
    }
}
