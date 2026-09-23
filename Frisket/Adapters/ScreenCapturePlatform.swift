import AppKit
@preconcurrency import ScreenCaptureKit
import QuartzCore
import ImageIO
import UniformTypeIdentifiers

@MainActor final class ScreenCapturePlatform: AreaCapturePlatform, FullScreenCapturePlatform {
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
        let selection = await overlay.select(on: screen)
        captureDisplayID = selection?.displayID
        return selection
    }

    func displayUnderPointer() -> FullScreenDisplay? {
        let pointer = NSEvent.mouseLocation
        captureDisplayID = nil
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        captureDisplayID = number.uint32Value
        return FullScreenDisplay(displayID: number.uint32Value, frame: screen.frame, scale: screen.backingScaleFactor)
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
        let ownApplications = available.applications.filter { $0.bundleIdentifier == request.excludingBundleIdentifier }
        // Fail closed: never capture if we cannot positively exclude this process.
        guard ownApplications.contains(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }) else {
            throw CapturePlatformError.unavailable
        }
        let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = request.sourceRect
        config.width = request.pixelWidth
        config.height = request.pixelHeight
        config.showsCursor = false
        config.capturesAudio = false
        config.captureMicrophone = false
        config.ignoreShadowsDisplay = true
        config.colorSpaceName = CGColorSpace.sRGB
        config.captureResolution = .best
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
