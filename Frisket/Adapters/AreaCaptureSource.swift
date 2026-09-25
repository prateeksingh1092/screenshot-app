import Foundation
import FrisketCore

public struct AreaSelection {
    let displayID: UInt32
    let displayFrame: CGRect // AppKit global points (bottom-left origin).
    let rect: CGRect
    let scale: CGFloat
    let spaceGeneration: UInt64 // Sampled when the rectangle is accepted.
}

public struct AreaCaptureRequest {
    let displayID: UInt32
    let sourceRect: CGRect // Display-local points (top-left origin), snapped to pixels.
    let pixelWidth: Int
    let pixelHeight: Int
    let excludingBundleIdentifier: String
    var additionalExcludedBundleIdentifiers: Set<String> = []
    var excludedBundleIdentifiers: Set<String> {
        additionalExcludedBundleIdentifiers.union([excludingBundleIdentifier])
    }
}

extension AreaCaptureRequest {
    /// The core computes the region; the adapter adds only who is left out of the pixels.
    init(region: RegionRequest, excludingBundleIdentifier: String, additionalExcludedBundleIdentifiers: Set<String>) {
        self.init(displayID: region.displayID, sourceRect: region.sourceRect,
                  pixelWidth: region.pixelWidth, pixelHeight: region.pixelHeight,
                  excludingBundleIdentifier: excludingBundleIdentifier,
                  additionalExcludedBundleIdentifiers: additionalExcludedBundleIdentifiers)
    }
}

/// The OS seam: prefetch completes before selection; all selection paths hide before pixels.
@MainActor public protocol AreaCapturePlatform: AnyObject {
    var spaceGeneration: UInt64 { get }
    func prefetchShareableContent() async throws
    func prepareSelection() async
    func selectArea() async -> AreaSelection?
    func hideSelection()
    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data
    func finishCapture()
}

@MainActor public final class AreaCaptureSource: CapturePixelSource {
    private let platform: any AreaCapturePlatform
    private let bundleIdentifier: String
    private let exclusions: @MainActor () -> Set<String>
    private let latency: CaptureLatencyLog?
    /// Uncompressed RGBA ceiling. Nil uses the encoded `maximumBytes` allowance.
    private let decodedByteCeiling: Int?
    public init(platform: any AreaCapturePlatform, bundleIdentifier: String,
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
        await platform.prepareSelection()
        let selection = await platform.selectArea()
        if selection != nil { latency?.selectionAccepted() }
        platform.hideSelection()
        guard let selection, selection.spaceGeneration == platform.spaceGeneration else { return .failure(.cancelled) }
        let display = SelectionDisplay(id: selection.displayID, frame: selection.displayFrame, scale: selection.scale)
        // Bound the raw bitmap too, before asking the OS to allocate it.
        let region: RegionRequest
        switch RegionRequest.area(selection.rect, on: display, decodedByteCeiling: decodedByteCeiling ?? maximumBytes) {
        case let .success(value): region = value
        case let .failure(failure): return .failure(failure)
        }
        let request = AreaCaptureRequest(region: region, excludingBundleIdentifier: bundleIdentifier,
                                         additionalExcludedBundleIdentifiers: exclusions())
        do {
            let data = try await platform.capture(request, maximumBytes: maximumBytes)
            // Validate at the core seam before any returned pixels can become Pending.
            guard selection.spaceGeneration == platform.spaceGeneration else { return .failure(.cancelled) }
            guard data.count <= maximumBytes else { return .failure(.unavailable) }
            return .success(CaptureImage(pngData: data, displayID: region.displayID))
        } catch let failure as CaptureSourceFailure {
            return .failure(failure)
        } catch {
            guard selection.spaceGeneration == platform.spaceGeneration else { return .failure(.cancelled) }
            return .failure(.unavailable)
        }
    }
}
