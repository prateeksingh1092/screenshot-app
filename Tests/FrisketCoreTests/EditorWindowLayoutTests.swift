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
