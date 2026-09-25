import Foundation
import FrisketCore

@MainActor protocol WindowCapturePlatform: AnyObject {
    /// Await shareable-content preparation before any selection UI is created.
    /// Returns both listings unjoined; `WindowSelection(rows:)` joins and filters them.
    func prepareWindows() async throws -> WindowRows
    /// The connected displays, read when the window's pixels arrive.
    func displays() -> [SelectionDisplay]
    func selectWindow(from selection: WindowSelection) async -> UInt32?
    func hideSelection()
    func capture(_ window: WindowCandidate, maximumBytes: Int) async throws -> Data
    func finishCapture()
}

@MainActor final class WindowCaptureSource: CapturePixelSource {
    private let platform: any WindowCapturePlatform
    private let ownProcessID: Int32
    private let bundleIdentifier: String
    private let exclusions: @MainActor () -> Set<String>

    init(platform: any WindowCapturePlatform, ownProcessID: Int32, bundleIdentifier: String,
         exclusions: @escaping @MainActor () -> Set<String> = { [] }) {
        self.platform = platform
        self.ownProcessID = ownProcessID
        self.bundleIdentifier = bundleIdentifier
        self.exclusions = exclusions
    }

    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        defer { platform.finishCapture() }
        do {
            let rows = try await platform.prepareWindows()
            let selection = WindowSelection(rows: rows, excluding: exclusions(), ownProcessID: ownProcessID,
                                            ownBundleIdentifier: bundleIdentifier)
            guard !selection.candidates.isEmpty else { return .failure(.window(.noWindow)) }
            let id = await platform.selectWindow(from: selection)
            platform.hideSelection()
            guard let id else { return .failure(.cancelled) }
            guard let window = selection.candidates.first(where: { $0.id == id }) else {
                return .failure(.window(.windowChanged))
            }
            let bytes = try await platform.capture(window, maximumBytes: maximumBytes)
            // The Thumbnail goes to the display holding the largest part of the window.
            let display = CaptureDisplays(platform.displays()).display(mostOverlapping: window.frame)
            return .success(CaptureImage(pngData: bytes, displayID: display?.id))
        } catch let failure as CaptureSourceFailure {
            // A platform failure with no named cause is still a window failure, never area advice.
            return .failure(failure == .unavailable ? .window(.systemRefused) : failure)
        } catch {
            return .failure(.window(.systemRefused))
        }
    }
}
