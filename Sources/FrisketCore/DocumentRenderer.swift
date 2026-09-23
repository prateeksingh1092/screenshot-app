import Foundation

/// A pure function from document to bitmap; the same document always renders the same pixels.
///
/// Crop is applied first. Each Solid redaction is then shifted into the cropped document,
/// scaled to output pixels, snapped outward (down on the minimum edges, up on the maximum
/// edges), clipped to the cropped image, and copied as opaque fill with no blending or
/// antialiasing. Sampling effects read that redacted composite; redactions are stamped
/// again afterwards. Stroke annotations draw last.
public enum DocumentRenderer {
    public static let stripHeight = 256

    public static func render(_ document: EditorDocument) -> Bitmap {
        var output = croppedBase(document.base, crop: document.edits.crop, scale: document.edits.scale)
        paint(&output, edits: document.edits, rowShift: 0, fullWidth: output.width, fullHeight: output.height)
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
        let rowsPerStrip = max(1, stripHeight)
        var row = 0
        while row < size.height {
            let count = min(rowsPerStrip, size.height - row)
            try body(renderWindow(edits: edits, startRow: row, rowCount: count, full: size, copyRows: copyRows))
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
        cropBounds(document.base, crop: document.edits.crop, scale: document.edits.scale)
    }

    private static func renderWindow(edits: DocumentEdits, startRow: Int, rowCount: Int,
                                     full: (width: Int, height: Int),
                                     copyRows: (Int, Int) -> Bitmap?) -> Bitmap {
        let halo = edits.effects.isEmpty ? 0 : 1
        let paddedStart = max(0, startRow - halo)
        let paddedEnd = min(full.height, startRow + rowCount + halo)
        var window = copyRows(paddedStart, paddedEnd - paddedStart)
            ?? Bitmap(width: full.width, height: rowCount, bytes: [UInt8](repeating: 0, count: full.width * rowCount * 4))!
        paint(&window, edits: edits, rowShift: paddedStart, fullWidth: full.width, fullHeight: full.height)
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

    private static func paint(_ output: inout Bitmap, edits: DocumentEdits, rowShift: Int,
                              fullWidth: Int, fullHeight: Int) {
        let fill = SolidRedaction.fill
        let scale = edits.scale
        let originX = edits.crop?.x ?? 0
        let originY = edits.crop?.y ?? 0
        fillRedactions(edits.redactions, on: &output, scale: scale, originX: originX, originY: originY,
                       fill: fill, rowShift: rowShift, fullWidth: fullWidth, fullHeight: fullHeight)
        for effect in edits.effects {
            apply(effect, on: &output, scale: scale, originX: originX, originY: originY,
                  rowShift: rowShift, fullWidth: fullWidth, fullHeight: fullHeight)
        }
        fillRedactions(edits.redactions, on: &output, scale: scale, originX: originX, originY: originY,
                       fill: fill, rowShift: rowShift, fullWidth: fullWidth, fullHeight: fullHeight)
        for annotation in edits.annotations {
            draw(annotation, on: &output, scale: scale, originX: originX, originY: originY,
                 rowShift: rowShift, fullWidth: fullWidth, fullHeight: fullHeight)
        }
    }

    private static func fillRedactions(_ redactions: [SolidRedaction], on output: inout Bitmap, scale: Double,
                                       originX: Double, originY: Double, fill: RGBAPixel,
                                       rowShift: Int, fullWidth: Int, fullHeight: Int) {
        for redaction in redactions {
            guard let bounds = snapped(x: redaction.x, y: redaction.y, width: redaction.width, height: redaction.height,
                                       scale: scale, originX: originX, originY: originY, rowShift: rowShift,
                                       fullWidth: fullWidth, fullHeight: fullHeight, in: output) else { continue }
            for y in bounds.minY..<bounds.maxY {
                for x in bounds.minX..<bounds.maxX {
                    let index = (y * output.width + x) * 4
                    output.bytes.replaceSubrange(index..<index + 4, with: [fill.red, fill.green, fill.blue, fill.alpha])
                }
            }
        }
    }

    private static func apply(_ effect: DocumentEffect, on output: inout Bitmap, scale: Double,
                              originX: Double, originY: Double, rowShift: Int, fullWidth: Int, fullHeight: Int) {
        let rectangle: (x: Double, y: Double, width: Double, height: Double)
        switch effect.kind {
        case let .blur(x, y, width, height), let .magnify(x, y, width, height):
            rectangle = (x, y, width, height)
        }
        guard let bounds = snapped(x: rectangle.x, y: rectangle.y, width: rectangle.width, height: rectangle.height,
                                   scale: scale, originX: originX, originY: originY, rowShift: rowShift,
                                   fullWidth: fullWidth, fullHeight: fullHeight, in: output) else { return }
        var next = output
        switch effect.kind {
        case .blur:
            for y in bounds.minY..<bounds.maxY {
                for x in bounds.minX..<bounds.maxX {
                    var red = 0, green = 0, blue = 0, alpha = 0
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let sampleX = min(max(x + dx, 0), output.width - 1)
                            let sampleY = min(max(y + dy, 0), output.height - 1)
                            let pixel = output.pixel(x: sampleX, y: sampleY)!
                            red += Int(pixel.red)
                            green += Int(pixel.green)
                            blue += Int(pixel.blue)
                            alpha += Int(pixel.alpha)
                        }
                    }
                    write(RGBAPixel(red: UInt8(red / 9), green: UInt8(green / 9),
                                    blue: UInt8(blue / 9), alpha: UInt8(alpha / 9)),
                          x: x, y: y, on: &next)
                }
            }
        case .magnify:
            for y in bounds.minY..<bounds.maxY {
                for x in bounds.minX..<bounds.maxX {
                    let sampleX = bounds.minX + (x - bounds.minX) / 2
                    let sampleY = bounds.minY + (y - bounds.minY) / 2
                    write(output.pixel(x: sampleX, y: sampleY)!, x: x, y: y, on: &next)
                }
            }
        }
        output = next
    }

    private static func snapped(x: Double, y: Double, width: Double, height: Double, scale: Double,
                                originX: Double, originY: Double, rowShift: Int,
                                fullWidth: Int, fullHeight: Int, in output: Bitmap)
    -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        func column(_ value: Double) -> Int { Int(min(max(value, 0), Double(fullWidth))) }
        func row(_ value: Double) -> Int { Int(min(max(value, 0), Double(fullHeight))) }
        let minX = column(((x - originX) * scale).rounded(.down))
        let rawMinY = row(((y - originY) * scale).rounded(.down))
        let maxX = column(((x - originX + width) * scale).rounded(.up))
        let rawMaxY = row(((y - originY + height) * scale).rounded(.up))
        let minY = max(0, rawMinY - rowShift)
        let maxY = min(output.height, rawMaxY - rowShift)
        return minX < maxX && minY < maxY ? (minX, minY, maxX, maxY) : nil
    }

    private static func write(_ pixel: RGBAPixel, x: Int, y: Int, on output: inout Bitmap) {
        let index = (y * output.width + x) * 4
        output.bytes.replaceSubrange(index..<index + 4, with: [pixel.red, pixel.green, pixel.blue, pixel.alpha])
    }

    private static func draw(_ annotation: DocumentAnnotation, on output: inout Bitmap, scale: Double,
                             originX: Double, originY: Double, rowShift: Int, fullWidth: Int, fullHeight: Int) {
        func column(_ value: Double) -> Int { Int(min(max(value, 0), Double(fullWidth))) }
        func row(_ value: Double) -> Int { Int(min(max(value, 0), Double(fullHeight))) - rowShift }
        func plot(_ x: Int, _ y: Int) {
            guard (0..<output.width).contains(x), (0..<output.height).contains(y) else { return }
            let stroke = DocumentAnnotation.stroke
            let index = (y * output.width + x) * 4
            output.bytes.replaceSubrange(index..<index + 4, with: [stroke.red, stroke.green, stroke.blue, stroke.alpha])
        }
        switch annotation.kind {
        case let .rectangle(x, y, width, height):
            let minX = column(((x - originX) * scale).rounded(.down))
            let minY = row(((y - originY) * scale).rounded(.down))
            let maxX = column(((x - originX + width) * scale).rounded(.up))
            let maxY = row(((y - originY + height) * scale).rounded(.up))
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
            let startX = Int(((x0 - originX) * scale).rounded())
            let startY = Int(((y0 - originY) * scale).rounded())
            let endX = Int(((x1 - originX) * scale).rounded())
            let endY = Int(((y1 - originY) * scale).rounded())
            plotLine(from: (startX, startY), to: (endX, endY), plot: plot)
            plotArrowHead(from: (startX, startY), to: (endX, endY), scale: scale, plot: plot)
        case let .text(x, y, characters):
            let originColumn = Int(((x - originX) * scale).rounded(.down))
            let originRow = Int(((y - originY) * scale).rounded(.down))
            let cell = max(1, Int(scale.rounded(.down)))
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
        let size = max(1, scale.rounded(.down))
        let ux = vx / length, uy = vy / length
        let backX = Double(end.0) - ux * size, backY = Double(end.1) - uy * size
        plot(Int((backX - uy * size).rounded()), Int((backY + ux * size).rounded()))
        plot(Int((backX + uy * size).rounded()), Int((backY - ux * size).rounded()))
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
