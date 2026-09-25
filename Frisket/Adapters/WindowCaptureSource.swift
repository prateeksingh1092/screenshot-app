import Foundation
import FrisketCore

@MainActor protocol WindowCapturePlatform: AnyObject {
    /// Await shareable-content preparation before any selection UI is created.
    func prepareWindows() async throws -> [WindowCandidate]
    func selectWindow(from selection: WindowSelection) async -> UInt32?
    func hideSelection()
    func capture(_ window: WindowCandidate, maximumBytes: Int) async throws -> Data
    func finishCapture()
}

@MainActor final class WindowCaptureSource: CapturePixelSource {
    private let platform: any WindowCapturePlatform
    private let ownProcessID: Int32
    private let bundleIdentifier: String

    init(platform: any WindowCapturePlatform, ownProcessID: Int32, bundleIdentifier: String) {
        self.platform = platform
        self.ownProcessID = ownProcessID
        self.bundleIdentifier = bundleIdentifier
    }

    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        defer { platform.finishCapture() }
        do {
            let windows = try await platform.prepareWindows()
            let selection = WindowSelection(windows: windows, ownProcessID: ownProcessID,
                                            ownBundleIdentifier: bundleIdentifier)
            guard !selection.candidates.isEmpty else { return .failure(.window(.noWindow)) }
            let id = await platform.selectWindow(from: selection)
            platform.hideSelection()
            guard let id else { return .failure(.cancelled) }
            guard let window = selection.candidates.first(where: { $0.id == id }) else {
                return .failure(.window(.windowChanged))
            }
            let bytes = try await platform.capture(window, maximumBytes: maximumBytes)
            return .success(CaptureImage(pngData: bytes))
        } catch let failure as CaptureSourceFailure {
            // A platform failure with no named cause is still a window failure, never area advice.
            return .failure(failure == .unavailable ? .window(.systemRefused) : failure)
        } catch {
            return .failure(.window(.systemRefused))
        }
    }
}
