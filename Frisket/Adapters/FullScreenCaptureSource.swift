import Foundation
import FrisketCore

struct FullScreenDisplay {
    let displayID: UInt32
    let frame: CGRect // AppKit global points; the request uses display-local points.
    let scale: CGFloat
}

@MainActor protocol FullScreenCapturePlatform: AnyObject {
    func prefetchShareableContent() async throws
    func displayUnderPointer() -> FullScreenDisplay?
    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data
    func finishCapture()
}

@MainActor final class FullScreenCaptureSource: CapturePixelSource {
    private let platform: any FullScreenCapturePlatform
    private let bundleIdentifier: String
    private let latency: CaptureLatencyLog?
    private let exclusions: @MainActor () -> Set<String>
    /// Uncompressed RGBA ceiling. Nil uses the encoded `maximumBytes` allowance.
    private let decodedByteCeiling: Int?
    init(platform: any FullScreenCapturePlatform, bundleIdentifier: String,
         exclusions: @escaping @MainActor () -> Set<String> = { [] },
         latency: CaptureLatencyLog? = nil, decodedByteCeiling: Int? = nil) {
        self.platform = platform
        self.bundleIdentifier = bundleIdentifier
        self.exclusions = exclusions
        self.latency = latency
        self.decodedByteCeiling = decodedByteCeiling
    }

    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        defer { platform.finishCapture() }
        do { try await platform.prefetchShareableContent() }
        catch let failure as CaptureSourceFailure { return .failure(failure) }
        catch { return .failure(.unavailable) }
        // Resolve once before awaiting pixels, so pointer motion cannot retarget the capture.
        guard let display = platform.displayUnderPointer(), display.scale.isFinite, display.scale > 0 else {
            return .failure(.unavailable)
        }
        latency?.selectionAccepted()
        let width = (display.frame.width * display.scale).rounded()
        let height = (display.frame.height * display.scale).rounded()
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              width < Double(Int.max), height < Double(Int.max),
              width * height * 4 <= Double(decodedByteCeiling ?? maximumBytes) else { return .failure(.unavailable) }
        let request = AreaCaptureRequest(displayID: display.displayID,
            sourceRect: CGRect(origin: .zero, size: display.frame.size),
            pixelWidth: Int(width), pixelHeight: Int(height), excludingBundleIdentifier: bundleIdentifier,
            additionalExcludedBundleIdentifiers: exclusions())
        do {
            let data = try await platform.capture(request, maximumBytes: maximumBytes)
            guard data.count <= maximumBytes else { return .failure(.unavailable) }
            return .success(CaptureImage(pngData: data))
        } catch let failure as CaptureSourceFailure {
            return .failure(failure)
        } catch {
            return .failure(.unavailable)
        }
    }
}
