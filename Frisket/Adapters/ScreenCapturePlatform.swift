import AppKit
@preconcurrency import ScreenCaptureKit
import QuartzCore
import ImageIO
import UniformTypeIdentifiers

@MainActor final class ScreenCapturePlatform: AreaCapturePlatform {
    private let overlay = SelectionOverlay()
    private var content: Task<ShareableSnapshot, Error>?
    private(set) var captureDisplayID: UInt32?

    func prefetchShareableContent() {
        // Started on shortcut/menu invocation, before waiting for selection.
        content = Task {
            ShareableSnapshot(try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true))
        }
    }

    func selectArea() async -> AreaSelection? {
        // A single pointer-position read, not a monitor. Selection remains on this display.
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return nil }
        let originFrame = screen.frame
        let originScale = screen.backingScaleFactor
        let originNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        // Sample only at invocation, while the overlay (including magnifier) is hidden.
        // The preview's pixels never become a pending capture or reach storage.
        hideSelection()
        var magnifier: SelectionMagnifier?
        if let content, let identifier = Bundle.main.bundleIdentifier,
           let available = try? await content.value.content {
            magnifier = try? await SelectionMagnifier.prepare(on: screen, content: available, excluding: identifier)
        }
        // A display change while preparing must not open a stale selection panel.
        guard let currentScreen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == originNumber
                && $0.frame == originFrame && $0.backingScaleFactor == originScale
        }) else { return nil }
        let selection = await overlay.select(on: currentScreen, magnifier: magnifier)
        captureDisplayID = selection?.displayID
        return selection
    }

    func hideSelection() {
        overlay.hide()
        CATransaction.flush()
    }

    func finishCapture() {
        content?.cancel()
        content = nil
    }

    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data {
        guard let content else { throw CapturePlatformError.unavailable }
        let available = try await content.value.content
        guard let display = available.displays.first(where: { $0.displayID == request.displayID }),
              NSScreen.screens.contains(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == request.displayID }) else {
            throw CapturePlatformError.unavailable
        }
        let filter = try ScreenCapturePolicy.filter(display: display, content: available,
                                                   excluding: request.excludingBundleIdentifier)
        let config = ScreenCapturePolicy.configuration(sourceRect: request.sourceRect,
                                                       pixelWidth: request.pixelWidth, pixelHeight: request.pixelHeight)
        // Own-app filtering remains the safety mechanism even if a window-server update lags.
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let bytes = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else {
            throw CapturePlatformError.unavailable
        }
        CGImageDestinationAddImage(encoder, image, nil)
        guard CGImageDestinationFinalize(encoder), bytes.length <= maximumBytes else { throw CapturePlatformError.unavailable }
        return bytes as Data
    }
}

private enum CapturePlatformError: Error { case unavailable }

// The SDK has not annotated SCShareableContent as Sendable. Keep its object graph
// on MainActor, including across the prefetch task result.
@MainActor private final class ShareableSnapshot {
    let content: SCShareableContent
    init(_ content: SCShareableContent) { self.content = content }
}
