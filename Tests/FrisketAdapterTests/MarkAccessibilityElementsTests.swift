import AppKit
import FrisketAdapters
import Testing

/// D31 (ticket 96): the canvas's marks must be accessibility elements that live as long as their
/// marks and report a role, label, screen frame and selected state.
@Suite @MainActor struct MarkAccessibilityElementsTests {
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    private static func canvas() -> (NSWindow, NSView) {
        let window = NSWindow(contentRect: CGRect(x: 100, y: 200, width: 300, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        let view = FlippedView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        window.contentView = view
        return (window, view)
    }

    private static let arrow = MarkAccessibilityElements.Mark(
        label: "Curved arrow from 10, 20 to 60, 20", frame: CGRect(x: 10, y: 20, width: 50, height: 30), selected: false)
    private static let box = MarkAccessibilityElements.Mark(
        label: "Box, 40 by 40 points at 100, 100", frame: CGRect(x: 100, y: 100, width: 40, height: 40), selected: true)

    @Test func d31EachMarkIsAnImageWithItsLabelScreenFrameParentAndSelectedState() throws {
        let (window, view) = Self.canvas()
        let marks = MarkAccessibilityElements(parent: view)
        let elements = marks.update([Self.arrow, Self.box])
        #expect(elements.count == 2, "D31: one element per mark")
        let arrow = try #require(elements.first)
        #expect(arrow.accessibilityRole() == .image, "D31: role")
        #expect(arrow.accessibilityLabel() == Self.arrow.label, "D31: label")
        #expect(arrow.accessibilityParent() as? NSView === view, "D31: parent")
        #expect(!arrow.isAccessibilitySelected(), "D31: selected state")
        #expect(elements[1].isAccessibilitySelected(), "D31: selected state")
        let expected = window.convertToScreen(view.convert(Self.arrow.frame, to: nil))
        #expect(arrow.accessibilityFrame() == expected, "D31: the frame is in screen coordinates, from the flipped canvas")
    }

    @Test func d31ElementsAreKeptUntilTheMarksChange() {
        let (window, view) = Self.canvas()
        let marks = MarkAccessibilityElements(parent: view)
        weak var first: NSAccessibilityElement?
        do {
            let elements = marks.update([Self.arrow, Self.box])
            first = elements.first
        }
        #expect(first != nil, "D31: the element outlives the call that made it")
        let again = marks.update([Self.arrow, Self.box])
        #expect(again.first === first, "D31: unchanged marks keep their elements")

        var reselected = Self.box
        reselected.selected = false
        var arrow = Self.arrow
        arrow.selected = true
        let changed = marks.update([arrow, reselected])
        #expect(changed.first === first, "a selection change updates the elements in place")
        #expect(changed[0].isAccessibilitySelected())
        #expect(!changed[1].isAccessibilitySelected())

        let fewer = marks.update([Self.box])
        #expect(fewer.count == 1)
        #expect(fewer[0].accessibilityLabel() == Self.box.label)
        #expect(marks.update([]).isEmpty)
        _ = window
    }
}
