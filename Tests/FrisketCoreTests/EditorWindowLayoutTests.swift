import Foundation
import FrisketCore
import Testing

@Suite struct EditorWindowLayoutTests {
    private let chrome = EditorWindowLayout.Chrome(toolbarHeight: 88, titlebarHeight: 28)
    private let builtInVisible = CGSize(width: 1792, height: 1090)

    @Test func smallCaptureOpensAtNaturalSizeWithoutTheOldToolbarMinimum() {
        let size = EditorWindowLayout.contentSize(document: CGSize(width: 320, height: 180),
                                                  visible: builtInVisible, chrome: chrome)
        #expect(size.width == 320)
        #expect(size.height == 268)
    }

    @Test func fullScreenCaptureWindowFitsOnTheVisibleDisplay() {
        let size = EditorWindowLayout.contentSize(document: CGSize(width: 1792, height: 1120),
                                                  visible: builtInVisible, chrome: chrome)
        #expect(size.width <= builtInVisible.width)
        #expect(size.height + chrome.titlebarHeight <= builtInVisible.height)
        let canvasHeight = size.height - chrome.toolbarHeight
        let aspect = size.width / canvasHeight
        #expect(abs(aspect - 1.6) < 0.001)
    }
}

/// D5: the editor's finish actions live in a bar inside the window, so they never overflow
/// into the toolbar's `>>` menu.
@Suite struct EditorActionBarTests {
    private let widths = [EditorWindowLayout.minimumContentWidth, EditorWindowLayout.defaultContentWidth]

    @Test func d5DoneCopySaveAndDragHandleFitInsideTheBarAtDefaultAndMinimumWidths() {
        for width in widths {
            let bar = EditorWindowLayout.actionBar(width: width)
            let bounds = CGRect(x: 0, y: 0, width: width, height: EditorWindowLayout.actionBarHeight)
            for frame in [bar.dragHandle, bar.copy, bar.save, bar.done] {
                #expect(frame.width > 0 && frame.height > 0)
                #expect(bounds.contains(frame), "\(frame) leaves the \(width)-point bar")
            }
            let frames = [bar.dragHandle, bar.copy, bar.save, bar.done]
            for (i, a) in frames.enumerated() {
                for b in frames[(i + 1)...] { #expect(!a.intersects(b), "\(a) overlaps \(b) at \(width)") }
            }
        }
    }

    @Test func doneIsTheTrailingActionAfterCopyAndSave() {
        let bar = EditorWindowLayout.actionBar(width: EditorWindowLayout.defaultContentWidth)
        #expect(bar.dragHandle.maxX < bar.copy.minX)
        #expect(bar.copy.maxX < bar.save.minX)
        #expect(bar.save.maxX < bar.done.minX)
        #expect(bar.done.maxX == EditorWindowLayout.defaultContentWidth - EditorWindowLayout.actionBarMargin)
    }

    @Test func theBarFollowsTheWindowWhenItWidens() {
        let narrow = EditorWindowLayout.actionBar(width: EditorWindowLayout.minimumContentWidth)
        let wide = EditorWindowLayout.actionBar(width: 1600)
        #expect(wide.done.maxX == 1600 - EditorWindowLayout.actionBarMargin)
        #expect(wide.dragHandle == narrow.dragHandle)
    }
}

/// D5: Return means Done only outside the label field; command keys go to the main menu.
@Suite struct EditorKeyTests {
    @Test func d5ReturnAndEnterMeanDoneOutsideTheLabelField() {
        #expect(EditorKey.action(characters: "\r", commandLike: false, editingText: false) == .done)
        #expect(EditorKey.action(characters: "\u{3}", commandLike: false, editingText: false) == .done)
    }

    @Test func d5ReturnInTheLabelFieldIsNotDone() {
        #expect(EditorKey.action(characters: "\r", commandLike: false, editingText: true) == nil)
        #expect(EditorKey.action(characters: "\u{3}", commandLike: false, editingText: true) == nil)
    }

    @Test func commandKeysAreLeftToTheMenu() {
        #expect(EditorKey.action(characters: "\r", commandLike: true, editingText: false) == nil)
        #expect(EditorKey.action(characters: "c", commandLike: true, editingText: false) == nil)
        #expect(EditorKey.action(characters: "s", commandLike: true, editingText: false) == nil)
    }

    @Test func lettersSelectToolsOnlyOutsideTheLabelField() {
        #expect(EditorKey.action(characters: "C", commandLike: false, editingText: false) == .tool("c"))
        #expect(EditorKey.action(characters: "t", commandLike: false, editingText: true) == nil)
        #expect(EditorKey.action(characters: nil, commandLike: false, editingText: false) == nil)
    }
}
