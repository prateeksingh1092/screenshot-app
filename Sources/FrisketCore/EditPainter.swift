import Accelerate
import CoreGraphics
import Foundation

/// Where crop-relative output pixels land in the buffer being painted.
///
/// `CaptureRenderer.flatten` paints at full size, where the grid is the identity. A downscaled
/// `CapturePreview` paints a buffer of `width × height` preview pixels standing for a
/// `captureWidth × captureHeight` capture: preview pixel `j` covers the capture interval
/// `[j·W/w, (j+1)·W/w)`. A box of output pixels maps to every preview pixel it touches (minimum
/// edges down, maximum edges up), so a Solid redaction covers each preview pixel whose block
/// holds any redacted pixel.
struct PixelGrid: Sendable {
    let captureWidth: Int, captureHeight: Int
    let width: Int, height: Int
    /// The crop's snapped top-left, in capture pixels.
    let origin: (x: Int, y: Int)
    /// The painted buffer's top-left, in preview pixels of the whole capture.
    let target: (x: Int, y: Int)
    /// The painted buffer's size.
    let size: (width: Int, height: Int)

    var isIdentity: Bool { width == captureWidth && height == captureHeight }

    /// Full size: output pixels are painted pixels.
    static func identity(output: (width: Int, height: Int), origin: (x: Int, y: Int)) -> PixelGrid {
        PixelGrid(captureWidth: output.width, captureHeight: output.height, width: output.width, height: output.height,
                  origin: origin, target: origin, size: output)
    }

    /// A downscaled grid for the output `(origin, output)` of a capture shown at `width × height`.
    static func preview(captureWidth: Int, captureHeight: Int, width: Int, height: Int,
                        origin: (x: Int, y: Int), output: (width: Int, height: Int)) -> PixelGrid {
        let minX = origin.x * width / captureWidth, minY = origin.y * height / captureHeight
        let maxX = ceilDivide((origin.x + output.width) * width, captureWidth)
        let maxY = ceilDivide((origin.y + output.height) * height, captureHeight)
        return PixelGrid(captureWidth: captureWidth, captureHeight: captureHeight, width: width, height: height,
                         origin: origin, target: (minX, minY), size: (max(1, maxX - minX), max(1, maxY - minY)))
    }

    /// Output pixels `[low, high)` on one axis, as the painted pixels they touch, clipped to the buffer.
    func columns(_ low: Int, _ high: Int) -> Range<Int> {
        span(low, high, origin: origin.x, capture: captureWidth, scaled: width, target: target.x, limit: size.width)
    }

    func rows(_ low: Int, _ high: Int) -> Range<Int> {
        span(low, high, origin: origin.y, capture: captureHeight, scaled: height, target: target.y, limit: size.height)
    }

    private func span(_ low: Int, _ high: Int, origin: Int, capture: Int, scaled: Int, target: Int, limit: Int) -> Range<Int> {
        let lower: Int, upper: Int
        if isIdentity {
            (lower, upper) = (low, high)
        } else {
            lower = (low + origin) * scaled / capture - target
            upper = Self.ceilDivide((high + origin) * scaled, capture) - target
        }
        let clippedLower = min(max(lower, 0), limit), clippedUpper = min(max(upper, 0), limit)
        return clippedLower..<max(clippedLower, clippedUpper)
    }

    private static func ceilDivide(_ value: Int, _ divisor: Int) -> Int { (value + divisor - 1) / divisor }
}

/// Paints edits over an already cropped buffer. `CaptureRenderer.flatten` and `CapturePreview.render`
/// both call it, so the delivered image equals the preview at full size.
///
/// Each Solid redaction is scaled to output pixels, snapped outward (down on the minimum edges, up on
/// the maximum edges), shifted by the crop's whole-pixel origin, clipped to the output, mapped through
/// the grid, and copied as opaque fill with no blending or antialiasing. Every mark therefore covers
/// the same content it would cover without the crop (D18). Blur (vImage) and Magnify (CoreGraphics)
/// then read only that redacted composite, inside their own box; redactions are stamped again
/// afterwards. Annotations draw last, natively (`AnnotationPainter`): a white plate, the redactions
/// once more, then ink.
enum EditPainter {
    /// One output pixel of white around annotation ink. It is a constant, never a sample of the capture.
    static let plate = RGBAPixel(red: 255, green: 255, blue: 255, alpha: 255)

    static func outputSize(width: Int, height: Int, edits: DocumentEdits) -> (width: Int, height: Int) {
        guard let crop = edits.crop else { return (width, height) }
        let (minX, minY) = cropOrigin(width: width, height: height, edits: edits)
        let maxX = clamp(((crop.x + crop.width) * edits.scale).rounded(.up), width)
        let maxY = clamp(((crop.y + crop.height) * edits.scale).rounded(.up), height)
        return minX < maxX && minY < maxY ? (maxX - minX, maxY - minY) : (width, height)
    }

    /// The crop's snapped top-left in pixels of the uncropped capture.
    static func cropOrigin(width: Int, height: Int, edits: DocumentEdits) -> (x: Int, y: Int) {
        guard let crop = edits.crop else { return (0, 0) }
        let maxX = clamp(((crop.x + crop.width) * edits.scale).rounded(.up), width)
        let maxY = clamp(((crop.y + crop.height) * edits.scale).rounded(.up), height)
        let minX = clamp((crop.x * edits.scale).rounded(.down), width)
        let minY = clamp((crop.y * edits.scale).rounded(.down), height)
        // An empty crop keeps the whole capture, as `outputSize` does.
        return minX < maxX && minY < maxY ? (minX, minY) : (0, 0)
    }

    private static func clamp(_ value: Double, _ limit: Int) -> Int { Int(min(max(value, 0), Double(limit))) }

    /// Paints redactions, effects, redactions again, then annotations. `output` is the crop's size.
    static func paint(_ buffer: inout RGBABuffer, edits: DocumentEdits, output: (width: Int, height: Int), grid: PixelGrid) {
        let redactions = edits.redactions.compactMap { redaction in
            box(redaction.x, redaction.y, redaction.width, redaction.height, edits: edits, output: output, grid: grid)
                .map { (box: $0, fill: redaction.colour) }
        }
        fill(redactions, on: &buffer)
        for effect in edits.effects {
            let r = effect.rectangle
            guard let bounds = box(r.x, r.y, r.width, r.height, edits: edits, output: output, grid: grid) else { continue }
            apply(effect, bounds, on: &buffer)
        }
        fill(redactions, on: &buffer)
        // Plates first, then the redactions again so no plate pixel lands on a redacted pixel,
        // then ink above everything (annotations draw above Solid redactions).
        guard !edits.annotations.isEmpty else { return }
        AnnotationPainter.draw(edits.annotations, layer: .plate, on: &buffer, scale: edits.scale, output: output, grid: grid)
        fill(redactions, on: &buffer)
        AnnotationPainter.draw(edits.annotations, layer: .ink, on: &buffer, scale: edits.scale, output: output, grid: grid)
    }

    typealias Box = (minX: Int, minY: Int, maxX: Int, maxY: Int)

    /// A rectangle in document points, snapped outward to output pixels, clipped to the output,
    /// then mapped through the grid to every painted pixel it touches.
    private static func box(_ x: Double, _ y: Double, _ width: Double, _ height: Double, edits: DocumentEdits,
                            output: (width: Int, height: Int), grid: PixelGrid) -> Box? {
        let scale = edits.scale, origin = grid.origin
        func column(_ value: Double) -> Int { Int(min(max(value - Double(origin.x), 0), Double(output.width))) }
        func row(_ value: Double) -> Int { Int(min(max(value - Double(origin.y), 0), Double(output.height))) }
        let columns = grid.columns(column((x * scale).rounded(.down)), column(((x + width) * scale).rounded(.up)))
        let rows = grid.rows(row((y * scale).rounded(.down)), row(((y + height) * scale).rounded(.up)))
        guard !columns.isEmpty, !rows.isEmpty else { return nil }
        return (columns.lowerBound, rows.lowerBound, columns.upperBound, rows.upperBound)
    }

    private static func fill(_ boxes: [(box: Box, fill: RGBAPixel)], on output: inout RGBABuffer) {
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

    private static func apply(_ effect: DocumentEffect, _ bounds: Box, on output: inout RGBABuffer) {
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

    private static func copyBox(_ bounds: Box, from output: RGBABuffer) -> [UInt8] {
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

    private static func writeBox(_ box: [UInt8], _ bounds: Box, to output: inout RGBABuffer) {
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
}

extension DocumentEffect {
    /// The effect's box in document points.
    var rectangle: (x: Double, y: Double, width: Double, height: Double) {
        switch kind {
        case let .blur(x, y, width, height), let .magnify(x, y, width, height): (x, y, width, height)
        }
    }
}
