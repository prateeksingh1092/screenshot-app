import AppKit

/// The editor canvas's marks as accessibility elements (ticket 84, D31). Each mark is an image
/// element with its VoiceOver label, its frame and its selected state, parented to the canvas.
///
/// AppKit keeps no strong reference to the elements a view returns from
/// `accessibilityChildren()`, so this object owns them: they live until the marks change.
/// Frames are given in the parent view's coordinates and set in its accessibility space, so AppKit
/// reports them in screen coordinates wherever the window is.
@MainActor public final class MarkAccessibilityElements {
    /// One mark: its label, its frame in the parent view's coordinates, and whether it is selected.
    public struct Mark: Equatable, Sendable {
        public var label: String
        public var frame: CGRect
        public var selected: Bool

        public init(label: String, frame: CGRect, selected: Bool) {
            self.label = label
            self.frame = frame
            self.selected = selected
        }
    }

    private unowned let parent: NSView
    private var marks: [Mark] = []
    public private(set) var elements: [NSAccessibilityElement] = []

    public init(parent: NSView) {
        self.parent = parent
    }

    /// Brings the elements up to date with `marks` and returns them. Unchanged marks keep their
    /// elements; with the same number of marks, each element is updated in place; otherwise the
    /// elements are rebuilt.
    @discardableResult
    public func update(_ marks: [Mark]) -> [NSAccessibilityElement] {
        // AppKit reads the parent-space frame from the view's bottom-left, even in a flipped view.
        let bounds = parent.bounds
        let marks = marks.map { mark in
            var mark = mark
            mark.frame.origin.x -= bounds.minX
            mark.frame.origin.y = parent.isFlipped ? bounds.maxY - mark.frame.maxY : mark.frame.minY - bounds.minY
            return mark
        }
        guard marks != self.marks else { return elements }
        if marks.count != elements.count {
            elements = marks.map { _ in
                let element = NSAccessibilityElement()
                element.setAccessibilityRole(.image)
                element.setAccessibilityParent(parent)
                return element
            }
        }
        for (element, mark) in zip(elements, marks) {
            element.setAccessibilityLabel(mark.label)
            element.setAccessibilityFrameInParentSpace(mark.frame)
            element.setAccessibilitySelected(mark.selected)
        }
        self.marks = marks
        return elements
    }
}
