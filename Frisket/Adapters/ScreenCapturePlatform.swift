import AppKit
import FrisketCore
import ScreenCaptureKit
import QuartzCore
import ImageIO
import UniformTypeIdentifiers

@MainActor public final class ScreenCapturePlatform: AreaCapturePlatform, FullScreenCapturePlatform {
    public private(set) var spaceGeneration: UInt64 = 0
    private var applicationGeneration: UInt64 = 0
    private lazy var overlay = SelectionOverlay()
    private let permission: ScreenCapturePermissionAdapter
    private var content: (any ScreenCaptureContent)?
    private var areaLayout: DisplaySelectionSession?
    private var selectionPointer: CGPoint = .zero
    private var selectionDisplays: [SelectionDisplay] = []

    private let loadContent: @MainActor () async throws -> any ScreenCaptureContent
    private let connectedDisplays: @MainActor () -> [SelectionDisplay]
    private let applicationNotifications: NotificationCenter
    private let exclusions: @MainActor () -> Set<String>
    /// The app's platform: live shareable content, the connected screens and workspace notifications.
    public convenience init(permission: ScreenCapturePermissionAdapter, exclusions: @escaping @MainActor () -> Set<String>) {
        self.init(permission: permission, exclusions: exclusions,
                  loadContent: {
                      ShareableScreenCaptureContent(content: try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true))
                  },
                  connectedDisplays: { NSScreen.screens.compactMap(\.selectionDisplay) },
                  applicationNotifications: NSWorkspace.shared.notificationCenter)
    }

    /// The test seam: synthetic content, displays and notifications.
    init(permission: ScreenCapturePermissionAdapter,
         exclusions: @escaping @MainActor () -> Set<String> = { [] },
         loadContent: @escaping @MainActor () async throws -> any ScreenCaptureContent,
         connectedDisplays: @escaping @MainActor () -> [SelectionDisplay],
         applicationNotifications: NotificationCenter) {
        self.permission = permission
        self.exclusions = exclusions
        self.loadContent = loadContent
        self.connectedDisplays = connectedDisplays
        self.applicationNotifications = applicationNotifications
    }

    public func prefetchShareableContent() async throws {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            applicationNotifications.addObserver(self, selector: #selector(applicationsChanged), name: name, object: nil)
        }
        areaLayout = nil
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

    public func prepareSelection() async {
        // One pointer read, not a monitor. A drag may start on any connected display.
        let pointer = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let displays = screens.compactMap(\.selectionDisplay)
        selectionPointer = pointer
        selectionDisplays = displays
        guard !displays.isEmpty else { return }
        areaLayout = DisplaySelectionSession(displays: displays, pointer: pointer)
        hideSelection()
    }

    public func discardSelectionPreviews() {}

    public func selectArea() async -> AreaSelection? {
        // A change on ANY display during preparation invalidates the whole layout.
        areaLayout?.updateDisplays(connectedDisplays())
        guard areaLayout?.isCancelled == false else { return nil }
        return await overlay.select(displays: selectionDisplays, pointer: selectionPointer,
                                    spaceGeneration: { self.spaceGeneration })
    }

    public func displayUnderPointer() -> SelectionDisplay? {
        CaptureDisplays(connectedDisplays()).display(at: NSEvent.mouseLocation)   // D14: top row included
    }

    public func hideSelection() {
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

    public func finishCapture() {
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

    func captureRegion(_ request: AreaCaptureRequest) async throws -> CGImage {
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
        return image
    }

    public func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data {
        let image = try await captureRegion(request)
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
