import AppKit
import FrisketCore
@preconcurrency import ScreenCaptureKit
import QuartzCore
import ImageIO
import UniformTypeIdentifiers

@MainActor final class ScreenCapturePlatform: AreaCapturePlatform, FullScreenCapturePlatform {
    private(set) var spaceGeneration: UInt64 = 0
    private lazy var overlay = SelectionOverlay()
    private let permission: ScreenCapturePermissionAdapter
    private var content: SCShareableContent?
    private var areaLayout: DisplaySelectionSession?
    private var selectionPointer: CGPoint = .zero
    private var selectionDisplays: [SelectionDisplay] = []
    private var magnifiers: [UInt32: SelectionMagnifier] = [:]
    private(set) var captureDisplayID: UInt32?

    init(permission: ScreenCapturePermissionAdapter) { self.permission = permission }

    func prefetchShareableContent() async throws {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        areaLayout = nil
        captureDisplayID = nil
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

    func prepareSelection() async {
        // One pointer read, not a monitor. A drag may start on any connected display.
        let pointer = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let displays = screens.compactMap(\.selectionDisplay)
        selectionPointer = pointer
        selectionDisplays = displays
        guard !displays.isEmpty else { return }
        areaLayout = DisplaySelectionSession(displays: displays, pointer: pointer)
        // Prepare all previews before ANY overlay is visible. No screen pixels
        // are sampled on hover, on a Space switch, or while selection is active.
        hideSelection()
        discardSelectionPreviews()
        if let available = content, let identifier = Bundle.main.bundleIdentifier {
            for screen in screens {
                guard let display = screen.selectionDisplay else { continue }
                magnifiers[display.id] = try? await SelectionMagnifier.prepare(on: screen, content: available,
                                                                            excluding: identifier)
            }
        }
    }

    func discardSelectionPreviews() { magnifiers.removeAll() }

    func selectArea() async -> AreaSelection? {
        // A change on ANY display during preparation invalidates the whole layout.
        areaLayout?.updateDisplays(NSScreen.screens.compactMap(\.selectionDisplay))
        guard areaLayout?.isCancelled == false else { return nil }
        let selection = await overlay.select(displays: selectionDisplays, pointer: selectionPointer,
                                             magnifiers: magnifiers, spaceGeneration: { self.spaceGeneration })
        discardSelectionPreviews()
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

    @objc private func spaceChanged() {
        spaceGeneration &+= 1
        discardSelectionPreviews()
        overlay.spaceChanged()
    }

    func finishCapture() {
        NSWorkspace.shared.notificationCenter.removeObserver(self,
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        content = nil
        areaLayout = nil
        selectionDisplays = []
        discardSelectionPreviews()
    }

    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data {
        let state = permission.refresh()
        guard state == .granted else { throw CaptureSourceFailure.permissionRequired(state) }
        guard let available = content else { throw CapturePlatformError.unavailable }
        areaLayout?.updateDisplays(NSScreen.screens.compactMap(\.selectionDisplay))
        guard areaLayout?.isCancelled != true else { throw CapturePlatformError.unavailable }
        guard let display = available.displays.first(where: { $0.displayID == request.displayID }),
              NSScreen.screens.contains(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == request.displayID }) else {
            throw CapturePlatformError.unavailable
        }
        let filter = try ScreenCapturePolicy.filter(display: display, content: available,
                                                   excluding: request.excludingBundleIdentifier)
        let config = ScreenCapturePolicy.configuration(sourceRect: request.sourceRect,
                                                       pixelWidth: request.pixelWidth, pixelHeight: request.pixelHeight)
        // Own-app filtering remains the safety mechanism even if a window-server update lags.
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw permission.failure(for: error)
        }
        let refreshed = permission.refresh()
        guard refreshed == .granted else { throw CaptureSourceFailure.permissionRequired(refreshed) }
        // Discard in-flight pixels if the layout changed while ScreenCaptureKit awaited.
        areaLayout?.updateDisplays(NSScreen.screens.compactMap(\.selectionDisplay))
        guard areaLayout?.isCancelled != true else { throw CapturePlatformError.unavailable }
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
