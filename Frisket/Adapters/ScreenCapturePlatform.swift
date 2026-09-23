import AppKit
import FrisketCore
@preconcurrency import ScreenCaptureKit
import QuartzCore
import ImageIO
import UniformTypeIdentifiers

@MainActor final class ScreenCapturePlatform: AreaCapturePlatform, FullScreenCapturePlatform {
    private(set) var spaceGeneration: UInt64 = 0
    private let overlay = SelectionOverlay()
    private var content: Task<ShareableSnapshot, Error>?
    private var areaLayout: DisplaySelectionSession?
    private var selectionPointer: CGPoint = .zero
    private var selectionDisplays: [SelectionDisplay] = []
    private var magnifiers: [UInt32: SelectionMagnifier] = [:]
    private(set) var captureDisplayID: UInt32?

    func prefetchShareableContent() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        areaLayout = nil
        captureDisplayID = nil
        // Started on shortcut/menu invocation, before waiting for selection.
        content = Task {
            ShareableSnapshot(try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true))
        }
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
        if let content, let identifier = Bundle.main.bundleIdentifier,
           let available = try? await content.value.content {
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
        content?.cancel()
        content = nil
        areaLayout = nil
        selectionDisplays = []
        discardSelectionPreviews()
    }

    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data {
        guard let content else { throw CapturePlatformError.unavailable }
        let available = try await content.value.content
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
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
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

// The SDK has not annotated SCShareableContent as Sendable. Keep its object graph
// on MainActor, including across the prefetch task result.
@MainActor private final class ShareableSnapshot {
    let content: SCShareableContent
    init(_ content: SCShareableContent) { self.content = content }
}
