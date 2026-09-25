import Foundation

/// The editor's tools, as the style bar sees them (ticket 92).
public enum EditorToolKind: CaseIterable, Sendable {
    case select, solidRedaction, crop, arrow, line, shape, text, blur, magnify
}

/// One style control in the style bar.
public enum StyleControl: Hashable, Sendable {
    case redactionColour, inkColour, arrowStyle, lineWidth, labelSize, labelStyle
}

/// Which style controls the editor shows (ticket 92, D29): the selected mark's when it has any,
/// or else the active tool's. The bar sits in the content area under the toolbar, so no control
/// ever falls into the toolbar's overflow menu.
public enum StyleBar {
    public static func controls(tool: EditorToolKind, selection: MarkReference?, in edits: DocumentEdits) -> [StyleControl] {
        if let selection {
            let marked = controls(for: selection, in: edits)
            if !marked.isEmpty { return marked }
        }
        return controls(for: tool)
    }

    static func controls(for tool: EditorToolKind) -> [StyleControl] {
        switch tool {
        case .solidRedaction: [.redactionColour]
        case .arrow: [.inkColour, .arrowStyle, .lineWidth]
        case .line, .shape: [.inkColour, .lineWidth]
        case .text: [.inkColour, .labelSize, .labelStyle]
        case .select, .crop, .blur, .magnify: []
        }
    }

    static func controls(for mark: MarkReference, in edits: DocumentEdits) -> [StyleControl] {
        switch mark {
        case .redaction(let index):
            return edits.redactions.indices.contains(index) ? [.redactionColour] : []
        case .effect:
            return []
        case .annotation(let index):
            guard edits.annotations.indices.contains(index) else { return [] }
            let annotation = edits.annotations[index]
            switch annotation.kind {
            case .rectangle: return [.inkColour, .lineWidth]
            case .arrow: return annotation.style == .line ? [.inkColour, .lineWidth] : [.inkColour, .arrowStyle, .lineWidth]
            case .text: return [.inkColour, .labelSize, .labelStyle]
            }
        }
    }
}

extension EditorWindowLayout {
    /// The style bar across the top of the content area, above the hint line (ticket 92).
    public static let styleBarHeight: CGFloat = 32
}
