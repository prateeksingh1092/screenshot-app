import AppKit
@preconcurrency import ScreenCaptureKit
import QuartzCore
import ImageIO
import UniformTypeIdentifiers
import FrisketCore

@MainActor final class ScreenCapturePlatform: AreaCapturePlatform, FullScreenCapturePlatform {
    private lazy var overlay = SelectionOverlay()
    private let permission: ScreenCapturePermissionAdapter
    private var content: SCShareableContent?
    private(set) var captureDisplayID: UInt32?

    init(permission: ScreenCapturePermissionAdapter) { self.permission = permission }

    func prefetchShareableContent() async throws {
        content = nil
        let state = permission.refresh()
        guard state == .granted else { throw CaptureSourceFailure.permissionRequired(state) }
        do {
            // This may present an OS alert. Await it with no overlay created.
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw permission.failure(for: error)
        }
        let refreshed = permission.refresh()
        guard refreshed == .granted else { throw CaptureSourceFailure.permissionRequired(refreshed) }
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
        content = nil
    }

    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data {
        let state = permission.refresh()
        guard state == .granted else { throw CaptureSourceFailure.permissionRequired(state) }
        guard let available = content else { throw CapturePlatformError.unavailable }
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
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw permission.failure(for: error)
        }
        let refreshed = permission.refresh()
        guard refreshed == .granted else { throw CaptureSourceFailure.permissionRequired(refreshed) }
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
