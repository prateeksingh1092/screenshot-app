import Foundation

/// A pure function from document to bitmap; the same document always renders the same pixels.
///
/// Crop is applied first, snapped outward to whole output pixels. Each Solid redaction is then
/// scaled to output pixels, snapped outward (down on the minimum edges, up on the maximum
/// edges), shifted by the crop's whole-pixel origin, clipped to the cropped image, and copied
/// as opaque fill with no blending or antialiasing. Every mark therefore covers the same
/// content it would cover without the crop (D18). Sampling effects read that redacted composite; redactions are stamped
/// again afterwards. Stroke annotations draw last.
public enum DocumentRenderer {
    public static let stripHeight = 256
    /// One output pixel of white around annotation ink. It is a constant, never a sample of the capture.
    public static let plate = RGBAPixel(red: 255, green: 255, blue: 255, alpha: 255)

    /// Document points to output pixels. No floor of 1: a fractional editor-proxy scale may round to 0.
    public static func outputCount(points: Int, scale: Double) -> Int {
        Int((Double(points) * scale).rounded())
    }

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
        let halo = (edits.effects.isEmpty && edits.annotations.isEmpty) ? 0 : 1
        let paddedStart = max(0, startRow - halo)
        let paddedEnd = min(full.height, startRow + rowCount + halo)
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
        let covered = edits.redactions.compactMap { redaction in
            snapped(x: redaction.x, y: redaction.y, width: redaction.width, height: redaction.height,
                    scale: scale, originX: originX, originY: originY, rowShift: rowShift,
                    fullWidth: fullWidth, fullHeight: fullHeight, in: output)
        }
        for annotation in edits.annotations {
            draw(annotation, on: &output, scale: scale, originX: originX, originY: originY,
                 rowShift: rowShift, fullWidth: fullWidth, fullHeight: fullHeight, covered: covered)
        }
    }

    private static func fillRedactions(_ redactions: [SolidRedaction], on output: inout Bitmap, scale: Double,
                                       originX: Int, originY: Int,
                                       rowShift: Int, fullWidth: Int, fullHeight: Int) {
        let boxes = redactions.compactMap { redaction in
            snapped(x: redaction.x, y: redaction.y, width: redaction.width, height: redaction.height,
                    scale: scale, originX: originX, originY: originY, rowShift: rowShift,
                    fullWidth: fullWidth, fullHeight: fullHeight, in: output).map { (box: $0, fill: redaction.colour) }
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
        let rectangle: (x: Double, y: Double, width: Double, height: Double)
        switch effect.kind {
        case let .blur(x, y, width, height), let .magnify(x, y, width, height):
            rectangle = (x, y, width, height)
        }
        guard let bounds = snapped(x: rectangle.x, y: rectangle.y, width: rectangle.width, height: rectangle.height,
                                   scale: scale, originX: originX, originY: originY, rowShift: rowShift,
                                   fullWidth: fullWidth, fullHeight: fullHeight, in: output) else { return }
        switch effect.kind {
        case .blur:
            // Six passes of the same 3×3 average. Samples stay inside the box, so a
            // solid redaction that fills the box cannot pick up colour from outside it.
            blurBox(bounds, on: &output)
        case .magnify:
            magnifyBox(bounds, on: &output)
        }
    }

    private static func blurBox(_ bounds: (minX: Int, minY: Int, maxX: Int, maxY: Int), on output: inout Bitmap) {
        let boxWidth = bounds.maxX - bounds.minX
        let boxHeight = bounds.maxY - bounds.minY
        guard boxWidth > 0, boxHeight > 0 else { return }
        let count = boxWidth * boxHeight * 4
        var source = [UInt8](repeating: 0, count: count)
        var destination = [UInt8](repeating: 0, count: count)
        output.bytes.withUnsafeBytes { raw in
            guard let pixels = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for row in 0..<boxHeight {
                let from = ((bounds.minY + row) * output.width + bounds.minX) * 4
                _ = source.withUnsafeMutableBytes { box in
                    memcpy(box.baseAddress! + row * boxWidth * 4, pixels + from, boxWidth * 4)
                }
            }
        }
        for _ in 0..<6 {
            source.withUnsafeBytes { sourceRaw in
                destination.withUnsafeMutableBytes { destinationRaw in
                    guard let src = sourceRaw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let dst = destinationRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                    for y in 0..<boxHeight {
                        for x in 0..<boxWidth {
                            var red = 0, green = 0, blue = 0, alpha = 0
                            for dy in -1...1 {
                                let sampleY = min(max(y + dy, 0), boxHeight - 1)
                                for dx in -1...1 {
                                    let sampleX = min(max(x + dx, 0), boxWidth - 1)
                                    let index = (sampleY * boxWidth + sampleX) * 4
                                    red += Int(src[index])
                                    green += Int(src[index + 1])
                                    blue += Int(src[index + 2])
                                    alpha += Int(src[index + 3])
                                }
                            }
                            let index = (y * boxWidth + x) * 4
                            dst[index] = UInt8(red / 9)
                            dst[index + 1] = UInt8(green / 9)
                            dst[index + 2] = UInt8(blue / 9)
                            dst[index + 3] = UInt8(alpha / 9)
                        }
                    }
                }
            }
            swap(&source, &destination)
        }
        output.bytes.withUnsafeMutableBytes { raw in
            guard let pixels = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for row in 0..<boxHeight {
                let to = ((bounds.minY + row) * output.width + bounds.minX) * 4
                _ = source.withUnsafeBytes { box in
                    memcpy(pixels + to, box.baseAddress! + row * boxWidth * 4, boxWidth * 4)
                }
            }
        }
    }

    private static func magnifyBox(_ bounds: (minX: Int, minY: Int, maxX: Int, maxY: Int), on output: inout Bitmap) {
        let boxWidth = bounds.maxX - bounds.minX
        let boxHeight = bounds.maxY - bounds.minY
        guard boxWidth > 0, boxHeight > 0 else { return }
        var magnified = [UInt8](repeating: 0, count: boxWidth * boxHeight * 4)
        output.bytes.withUnsafeBytes { raw in
            guard let pixels = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for y in 0..<boxHeight {
                for x in 0..<boxWidth {
                    let from = ((bounds.minY + y / 2) * output.width + bounds.minX + x / 2) * 4
                    let to = (y * boxWidth + x) * 4
                    magnified[to] = pixels[from]
                    magnified[to + 1] = pixels[from + 1]
                    magnified[to + 2] = pixels[from + 2]
                    magnified[to + 3] = pixels[from + 3]
                }
            }
        }
        output.bytes.withUnsafeMutableBytes { raw in
            guard let pixels = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for row in 0..<boxHeight {
                let to = ((bounds.minY + row) * output.width + bounds.minX) * 4
                _ = magnified.withUnsafeBytes { box in
                    memcpy(pixels + to, box.baseAddress! + row * boxWidth * 4, boxWidth * 4)
                }
            }
        }
    }

    private static func snapped(x: Double, y: Double, width: Double, height: Double, scale: Double,
                                originX: Int, originY: Int, rowShift: Int,
                                fullWidth: Int, fullHeight: Int, in output: Bitmap)
    -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        func column(_ value: Double) -> Int { Int(min(max(value, 0), Double(fullWidth))) }
        func row(_ value: Double) -> Int { Int(min(max(value, 0), Double(fullHeight))) }
        let minX = column((x * scale).rounded(.down) - Double(originX))
        let rawMinY = row((y * scale).rounded(.down) - Double(originY))
        let maxX = column(((x + width) * scale).rounded(.up) - Double(originX))
        let rawMaxY = row(((y + height) * scale).rounded(.up) - Double(originY))
        let minY = max(0, rawMinY - rowShift)
        let maxY = min(output.height, rawMaxY - rowShift)
        return minX < maxX && minY < maxY ? (minX, minY, maxX, maxY) : nil
    }

    private static func write(_ pixel: RGBAPixel, x: Int, y: Int, on output: inout Bitmap) {
        let index = (y * output.width + x) * 4
        output.bytes.withUnsafeMutableBytes { raw in
            guard let pixels = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            pixels[index] = pixel.red
            pixels[index + 1] = pixel.green
            pixels[index + 2] = pixel.blue
            pixels[index + 3] = pixel.alpha
        }
    }

    private static func draw(_ annotation: DocumentAnnotation, on output: inout Bitmap, scale: Double,
                             originX: Int, originY: Int, rowShift: Int, fullWidth: Int, fullHeight: Int,
                             covered: [(minX: Int, minY: Int, maxX: Int, maxY: Int)]) {
        func column(_ value: Double) -> Int { Int(min(max(value, 0), Double(fullWidth))) }
        func row(_ value: Double) -> Int { Int(min(max(value, 0), Double(fullHeight))) - rowShift }
        let pen = max(2, Int((2 * scale).rounded()))
        var ink = Set<Int>()
        func plot(_ x: Int, _ y: Int) {
            let half = pen / 2
            for dy in 0..<pen {
                for dx in 0..<pen {
                    let px = x - half + dx
                    let py = y - half + dy
                    guard (0..<output.width).contains(px), (0..<output.height).contains(py) else { continue }
                    ink.insert(py * output.width + px)
                }
            }
        }
        switch annotation.kind {
        case let .rectangle(x, y, width, height):
            let minX = column((x * scale).rounded(.down) - Double(originX))
            let minY = row((y * scale).rounded(.down) - Double(originY))
            let maxX = column(((x + width) * scale).rounded(.up) - Double(originX))
            let maxY = row(((y + height) * scale).rounded(.up) - Double(originY))
            guard minX < maxX, minY < maxY else { return }
            for x in minX..<maxX {
                plot(x, minY)
                plot(x, maxY - 1)
            }
            for y in minY..<maxY {
                plot(minX, y)
                plot(maxX - 1, y)
            }
        case let .arrow(x0, y0, x1, y1):
            let startX = Int((x0 * scale).rounded()) - originX
            let startY = Int((y0 * scale).rounded()) - originY
            let endX = Int((x1 * scale).rounded()) - originX
            let endY = Int((y1 * scale).rounded()) - originY
            plotLine(from: (startX, startY), to: (endX, endY), plot: plot)
            plotArrowHead(from: (startX, startY), to: (endX, endY), scale: scale, plot: plot)
        case let .text(x, y, characters):
            let originColumn = Int((x * scale).rounded(.down) - Double(originX))
            let originRow = Int((y * scale).rounded(.down) - Double(originY))
            let cell = max(2, Int((2 * scale).rounded()))
            var cursor = 0
            for character in AnnotationFont.glyphs(in: characters) {
                for glyphRow in 0..<AnnotationFont.height {
                    guard let bits = AnnotationFont.row(character, glyphRow) else { continue }
                    for (glyphColumn, bit) in bits.enumerated() where bit == "#" {
                        for dy in 0..<cell {
                            for dx in 0..<cell {
                                plot(originColumn + cursor * cell + glyphColumn * cell + dx,
                                     originRow + glyphRow * cell + dy)
                            }
                        }
                    }
                }
                cursor += AnnotationFont.advance
            }
        }
        func redacted(_ x: Int, _ y: Int) -> Bool {
            covered.contains { x >= $0.minX && x < $0.maxX && y >= $0.minY && y < $0.maxY }
        }
        var ring = Set<Int>()
        for index in ink {
            let x = index % output.width
            let y = index / output.width
            for oy in -1...1 {
                for ox in -1...1 where ox != 0 || oy != 0 {
                    let nx = x + ox
                    let ny = y + oy
                    guard (0..<output.width).contains(nx), (0..<output.height).contains(ny) else { continue }
                    let neighbour = ny * output.width + nx
                    if ink.contains(neighbour) || redacted(nx, ny) { continue }
                    ring.insert(neighbour)
                }
            }
        }
        for index in ring {
            write(plate, x: index % output.width, y: index / output.width, on: &output)
        }
        for index in ink {
            write(DocumentAnnotation.stroke, x: index % output.width, y: index / output.width, on: &output)
        }
    }

    private static func plotLine(from start: (Int, Int), to end: (Int, Int), plot: (Int, Int) -> Void) {
        var x = start.0, y = start.1
        let dx = abs(end.0 - start.0), dy = -abs(end.1 - start.1)
        let stepX = start.0 < end.0 ? 1 : -1, stepY = start.1 < end.1 ? 1 : -1
        var error = dx + dy
        while true {
            plot(x, y)
            if x == end.0 && y == end.1 { break }
            let doubled = 2 * error
            if doubled >= dy { error += dy; x += stepX }
            if doubled <= dx { error += dx; y += stepY }
        }
    }

    private static func plotArrowHead(from start: (Int, Int), to end: (Int, Int), scale: Double,
                                      plot: (Int, Int) -> Void) {
        let vx = Double(end.0 - start.0), vy = Double(end.1 - start.1)
        let length = (vx * vx + vy * vy).squareRoot()
        guard length > 0 else { return }
        let size = max(8, 10 * scale)
        let ux = vx / length, uy = vy / length
        let backX = Double(end.0) - ux * size, backY = Double(end.1) - uy * size
        let tip = (end.0, end.1)
        let wingA = (Int((backX - uy * size).rounded()), Int((backY + ux * size).rounded()))
        let wingB = (Int((backX + uy * size).rounded()), Int((backY - ux * size).rounded()))
        plotLine(from: tip, to: wingA, plot: plot)
        plotLine(from: tip, to: wingB, plot: plot)
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
