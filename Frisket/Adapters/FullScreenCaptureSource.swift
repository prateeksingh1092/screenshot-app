import Foundation
import FrisketCore

@MainActor public protocol FullScreenCapturePlatform: AnyObject {
    func prefetchShareableContent() async throws
    func displayUnderPointer() -> SelectionDisplay?
    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data
    func finishCapture()
}

@MainActor public final class FullScreenCaptureSource: CapturePixelSource {
    private let platform: any FullScreenCapturePlatform
    private let bundleIdentifier: String
    private let latency: CaptureLatencyLog?
    private let exclusions: @MainActor () -> Set<String>
    /// Uncompressed RGBA ceiling. Nil uses the encoded `maximumBytes` allowance.
    private let decodedByteCeiling: Int?
    public init(platform: any FullScreenCapturePlatform, bundleIdentifier: String,
         exclusions: @escaping @MainActor () -> Set<String> = { [] },
         latency: CaptureLatencyLog? = nil, decodedByteCeiling: Int? = nil) {
        self.platform = platform
        self.bundleIdentifier = bundleIdentifier
        self.exclusions = exclusions
        self.latency = latency
        self.decodedByteCeiling = decodedByteCeiling
    }

    public func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        defer { platform.finishCapture() }
        do { try await platform.prefetchShareableContent() }
        catch let failure as CaptureSourceFailure { return .failure(failure) }
        catch { return .failure(.unavailable) }
        // Resolve once before awaiting pixels, so pointer motion cannot retarget the capture.
        guard let display = platform.displayUnderPointer() else { return .failure(.unavailable) }
        latency?.selectionAccepted()
        guard case let .success(region) = RegionRequest.fullScreen(display,
                decodedByteCeiling: decodedByteCeiling ?? maximumBytes) else { return .failure(.unavailable) }
        let request = AreaCaptureRequest(region: region, excludingBundleIdentifier: bundleIdentifier,
                                         additionalExcludedBundleIdentifiers: exclusions())
        do {
            let data = try await platform.capture(request, maximumBytes: maximumBytes)
            guard data.count <= maximumBytes else { return .failure(.unavailable) }
            return .success(CaptureImage(pngData: data, displayID: region.displayID))
        } catch let failure as CaptureSourceFailure {
            return .failure(failure)
        } catch {
            return .failure(.unavailable)
        }
    }
}
