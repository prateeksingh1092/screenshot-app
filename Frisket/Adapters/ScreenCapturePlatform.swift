import AppKit
import FrisketCore
@preconcurrency import ScreenCaptureKit
import QuartzCore
import ImageIO
import UniformTypeIdentifiers

@MainActor final class ScreenCapturePlatform: AreaCapturePlatform, FullScreenCapturePlatform {
    private(set) var spaceGeneration: UInt64 = 0
    private var applicationGeneration: UInt64 = 0
    private lazy var overlay = SelectionOverlay()
    private let permission: ScreenCapturePermissionAdapter
    private var content: (any ScreenCaptureContent)?
    private var areaLayout: DisplaySelectionSession?
    private var selectionPointer: CGPoint = .zero
    private var selectionDisplays: [SelectionDisplay] = []
    private var magnifiers: [UInt32: SelectionMagnifier] = [:]
    private(set) var captureDisplayID: UInt32?

    private let loadContent: @MainActor () async throws -> any ScreenCaptureContent
    private let connectedDisplays: @MainActor () -> [SelectionDisplay]
    private let applicationNotifications: NotificationCenter
    private let exclusions: @MainActor () -> Set<String>
    init(permission: ScreenCapturePermissionAdapter,
         exclusions: @escaping @MainActor () -> Set<String> = { [] },
         loadContent: @escaping @MainActor () async throws -> any ScreenCaptureContent = {
             ShareableScreenCaptureContent(content: try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true))
         },
         connectedDisplays: @escaping @MainActor () -> [SelectionDisplay] = { NSScreen.screens.compactMap(\.selectionDisplay) },
         applicationNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.permission = permission
        self.exclusions = exclusions
        self.loadContent = loadContent
        self.connectedDisplays = connectedDisplays
        self.applicationNotifications = applicationNotifications
    }

    func prefetchShareableContent() async throws {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            applicationNotifications.addObserver(self, selector: #selector(applicationsChanged), name: name, object: nil)
        }
        areaLayout = nil
        captureDisplayID = nil
        content = nil
        let state = permission.refresh()
        guard state == .granted else { throw CaptureSourceFailure.permissionRequired(state) }
        do {
            // This may present an OS alert. Await it with no overlay created.
            content = try await loadContent()
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
        if content != nil, let identifier = Bundle.main.bundleIdentifier {
            for screen in screens {
                guard let display = screen.selectionDisplay else { continue }
                let generation = applicationGeneration
                // Each frozen preview is also a capture; refresh after earlier
                // asynchronous previews rather than reusing prefetch identities.
                guard let available = try? await loadContent(), generation == applicationGeneration else { continue }
                magnifiers[display.id] = try? await available.prepareMagnifier(on: screen,
                                                                            excluding: identifier, additionalExclusions: exclusions())
                if generation != applicationGeneration { discardSelectionPreviews() }
            }
        }
    }

    func discardSelectionPreviews() { magnifiers.removeAll() }

    func selectArea() async -> AreaSelection? {
        // A change on ANY display during preparation invalidates the whole layout.
        areaLayout?.updateDisplays(connectedDisplays())
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

    @objc private func applicationsChanged() {
        applicationGeneration &+= 1
        discardSelectionPreviews()
    }

    func finishCapture() {
        NSWorkspace.shared.notificationCenter.removeObserver(self,
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            applicationNotifications.removeObserver(self, name: name, object: nil)
        }
        content = nil
        areaLayout = nil
        selectionDisplays = []
        discardSelectionPreviews()
    }

    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data {
        let state = permission.refresh()
        guard state == .granted else { throw CaptureSourceFailure.permissionRequired(state) }
        guard content != nil else { throw CapturePlatformError.unavailable }
        let generation = applicationGeneration
        // Selection can last arbitrarily long. Resolve process identities again
        // immediately before filtering; a prefetched application list is stale.
        let available: any ScreenCaptureContent
        do {
            available = try await loadContent()
        } catch {
            throw permission.failure(for: error)
        }
        guard generation == applicationGeneration else { throw CapturePlatformError.unavailable }
        areaLayout?.updateDisplays(connectedDisplays())
        guard areaLayout?.isCancelled != true else { throw CapturePlatformError.unavailable }
        guard connectedDisplays().contains(where: { $0.id == request.displayID }) else {
            throw CapturePlatformError.unavailable
        }
        let image: CGImage
        do {
            image = try await available.captureImage(request, additionalExclusions: exclusions())
        } catch {
            throw permission.failure(for: error)
        }
        let refreshed = permission.refresh()
        guard refreshed == .granted else { throw CaptureSourceFailure.permissionRequired(refreshed) }
        // SCScreenshotManager cannot update an in-flight filter. Never deliver
        // pixels if a process may have appeared/relaunched after the snapshot.
        guard generation == applicationGeneration else { throw CapturePlatformError.unavailable }
        // Discard in-flight pixels if the layout changed while ScreenCaptureKit awaited.
        areaLayout?.updateDisplays(connectedDisplays())
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
