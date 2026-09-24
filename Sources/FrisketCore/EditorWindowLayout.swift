import Foundation

/// Sizes the editor so the capture is shown at natural size when it fits, and
/// scaled down uniformly when chrome plus the image would overflow the display.
public struct EditorWindowLayout: Sendable {
    public struct Chrome: Equatable, Sendable {
        public var toolbarHeight: CGFloat
        public var titlebarHeight: CGFloat
        public init(toolbarHeight: CGFloat, titlebarHeight: CGFloat) {
            self.toolbarHeight = toolbarHeight
            self.titlebarHeight = titlebarHeight
        }
    }

    /// Window content size, excluding the titlebar.
    public static func contentSize(document: CGSize, visible: CGSize, chrome: Chrome) -> CGSize {
        guard document.width > 0, document.height > 0, visible.width > 0, visible.height > 0 else {
            return CGSize(width: 1, height: max(chrome.toolbarHeight + 1, 1))
        }
        let maxCanvasHeight = max(visible.height - chrome.titlebarHeight - chrome.toolbarHeight, 1)
        let scale = min(visible.width / document.width, maxCanvasHeight / document.height, 1)
        return CGSize(width: document.width * scale,
                      height: document.height * scale + chrome.toolbarHeight)
    }
}
