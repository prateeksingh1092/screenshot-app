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
        guard let redaction = SolidRedaction(x: min(start.x, end.x), y: min(start.y, end.y),
                                             width: abs(end.x - start.x), height: abs(end.y - start.y)) else { return false }
        edits.redactions.append(redaction)
        return true
    }
}
