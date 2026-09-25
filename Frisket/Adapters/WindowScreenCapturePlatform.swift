import AppKit
@preconcurrency import ScreenCaptureKit
import QuartzCore
import ImageIO
import UniformTypeIdentifiers
import FrisketCore

@MainActor final class WindowScreenCapturePlatform: NSObject, WindowCapturePlatform {
    private let permission: ScreenCapturePermissionAdapter
    private let bundleIdentifier: String
    private let exclusions: @MainActor () -> Set<String>
    private lazy var overlay = WindowSelectionOverlay()
    private var content: SCShareableContent?
    private var environmentGeneration = 0
    private var selectionGeneration = 0

    init(permission: ScreenCapturePermissionAdapter, bundleIdentifier: String,
         exclusions: @escaping @MainActor () -> Set<String> = { [] }) {
        self.permission = permission
        self.bundleIdentifier = bundleIdentifier
        self.exclusions = exclusions
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(environmentChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    func prepareWindows() async throws -> WindowRows {
        selectionGeneration = environmentGeneration
        let windows = try await loadWindows()
        guard selectionGeneration == environmentGeneration else { throw CaptureSourceFailure.cancelled }
        return windows
    }

    func displays() -> [SelectionDisplay] { NSScreen.screens.compactMap(\.selectionDisplay) }

    /// Fetches both listings; `WindowSelection(rows:)` joins them. ScreenCaptureKit is authoritative
    /// for shareability; CG supplies metadata-only front-to-back order.
    private func loadWindows() async throws -> WindowRows {
        content = nil
        try requirePermission()
        let available: SCShareableContent
        do {
            available = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch { throw permission.failure(for: error) }
        try requirePermission()
        guard let ordered = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else {
            throw CaptureSourceFailure.unavailable
        }
        content = available
        // Do not use isActive: off-screen Stage Manager windows can be active.
        return WindowRows(
            ordered: ordered.compactMap { entry in
                guard let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { return nil }
                return WindowListRow(id: id,
                    ownerProcessID: (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                    layer: (entry[kCGWindowLayer as String] as? NSNumber)?.intValue,
                    isOnScreen: entry[kCGWindowIsOnscreen as String] as? Bool == true)
            },
            shareable: available.windows.map { window in
                ShareableWindowRow(id: window.windowID, ownerProcessID: window.owningApplication?.processID,
                    bundleIdentifier: window.owningApplication?.bundleIdentifier, frame: window.frame,
                    layer: window.windowLayer, isOnScreen: window.isOnScreen)
            })
    }

    func selectWindow(from selection: WindowSelection) async -> UInt32? {
        guard selectionGeneration == environmentGeneration else { return nil }
        return await overlay.select(from: selection)
    }

    func hideSelection() {
        overlay.hide()
        CATransaction.flush()
    }

    func finishCapture() { content = nil }

    /// Uncompressed RGBA ceiling. Nil uses the encoded `maximumBytes` allowance.
    var decodedByteCeiling: Int?

    func capture(_ selected: WindowCandidate, maximumBytes: Int) async throws -> Data {
        // Selection has already been hidden. Refresh after clicking so closed,
        // minimized, moved-to-another-Space, or recycled windows fail closed.
        guard selectionGeneration == environmentGeneration else { throw CaptureSourceFailure.cancelled }
        let current = try await loadWindows()
        guard selectionGeneration == environmentGeneration else { throw CaptureSourceFailure.cancelled }
        let selection = WindowSelection(rows: current, excluding: exclusions(),
            ownProcessID: ProcessInfo.processInfo.processIdentifier, ownBundleIdentifier: bundleIdentifier)
        guard let candidate = selection.candidates.first(where: { $0.id == selected.id }),
              candidate.ownerProcessID == selected.ownerProcessID,
              candidate.bundleIdentifier == selected.bundleIdentifier,
              let window = content?.windows.first(where: { $0.windowID == candidate.id }) else {
            throw CaptureSourceFailure.window(.windowChanged)
        }
        // An allowlist containing exactly one foreign window excludes every Frisket
        // window, including panels created after enumeration. No sharing flags.
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let width = (filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded(.up)
        let height = (filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded(.up)
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              width < Double(Int.max), height < Double(Int.max) else { throw CaptureSourceFailure.window(.windowChanged) }
        guard width * height * 4 <= Double(decodedByteCeiling ?? maximumBytes) else {
            throw CaptureSourceFailure.window(.tooLarge)
        }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(width)
        configuration.height = Int(height)
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.captureMicrophone = false
        configuration.includeChildWindows = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.captureResolution = .best
        try requirePermission()
        let image: CGImage
        do { image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) }
        catch { throw permission.failure(for: error) }
        try requirePermission()
        guard selectionGeneration == environmentGeneration else { throw CaptureSourceFailure.cancelled }
        let bytes = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else {
            throw CaptureSourceFailure.unavailable
        }
        CGImageDestinationAddImage(encoder, image, nil)
        guard CGImageDestinationFinalize(encoder) else { throw CaptureSourceFailure.window(.systemRefused) }
        guard bytes.length <= maximumBytes else { throw CaptureSourceFailure.window(.tooLarge) }
        return bytes as Data
    }

    private func requirePermission() throws {
        let state = permission.refresh()
        guard state == .granted else { throw CaptureSourceFailure.permissionRequired(state) }
    }
    @objc private func environmentChanged() { environmentGeneration += 1 }
}
