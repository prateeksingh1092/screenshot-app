import Foundation
import FrisketCore

/// A canvas tool. The editor lists every tool in its palette and hands the active one
/// each completed canvas drag, in document points. Later tools (crop, arrows, shapes,
/// text, blur) add conformers here; the document and renderer stay the only pixel path.
@MainActor protocol EditorTool: AnyObject {
    var title: String { get }
    var accessibilityLabel: String { get }
    var keyEquivalent: String { get }
    /// Applies a drag from `start` to `end`; returns false when the drag changes nothing.
    func applyDrag(from start: CGPoint, to end: CGPoint, to edits: inout DocumentEdits) -> Bool
}

@MainActor final class SolidRedactionTool: EditorTool {
    let title = "Solid Redaction"
    let accessibilityLabel = "Solid redaction tool"
    let keyEquivalent = "r"

    func applyDrag(from start: CGPoint, to end: CGPoint, to edits: inout DocumentEdits) -> Bool {
        let originX = edits.crop?.x ?? 0
        let originY = edits.crop?.y ?? 0
        guard let redaction = SolidRedaction(x: min(start.x, end.x) + originX, y: min(start.y, end.y) + originY,
                                             width: abs(end.x - start.x), height: abs(end.y - start.y)) else { return false }
        edits.redactions.append(redaction)
        return true
    }
}

@MainActor final class CropTool: EditorTool {
    let title = "Crop"
    let accessibilityLabel = "Crop tool"
    let keyEquivalent = "c"

    func applyDrag(from start: CGPoint, to end: CGPoint, to edits: inout DocumentEdits) -> Bool {
        let originX = edits.crop?.x ?? 0
        let originY = edits.crop?.y ?? 0
        guard let crop = DocumentCrop(x: min(start.x, end.x) + originX, y: min(start.y, end.y) + originY,
                                      width: abs(end.x - start.x), height: abs(end.y - start.y)) else { return false }
        edits.crop = crop
        return true
    }
}
