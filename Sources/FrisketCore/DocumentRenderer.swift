import Foundation

/// A pure function from document to bitmap; the same document always renders the same pixels.
///
/// Each Solid redaction is scaled to output pixels, snapped outward (down on the minimum
/// edges, up on the maximum edges), clipped to the image, and copied over the base as
/// opaque fill with no blending or antialiasing.
public enum DocumentRenderer {
    public static func render(_ document: EditorDocument) -> Bitmap {
        var output = document.base
        let fill = SolidRedaction.fill
        let scale = document.edits.scale
        for redaction in document.edits.redactions {
            // Clamp in floating point first: Int conversion traps on out-of-range values.
            func column(_ value: Double) -> Int { Int(min(max(value, 0), Double(output.width))) }
            func row(_ value: Double) -> Int { Int(min(max(value, 0), Double(output.height))) }
            let minX = column((redaction.x * scale).rounded(.down))
            let minY = row((redaction.y * scale).rounded(.down))
            let maxX = column(((redaction.x + redaction.width) * scale).rounded(.up))
            let maxY = row(((redaction.y + redaction.height) * scale).rounded(.up))
            guard minX < maxX, minY < maxY else { continue }
            for y in minY..<maxY {
                for x in minX..<maxX {
                    let index = (y * output.width + x) * 4
                    output.bytes.replaceSubrange(index..<index + 4, with: [fill.red, fill.green, fill.blue, fill.alpha])
                }
            }
        }
        return output
    }
}
