import Foundation
import FrisketCore

struct AreaSelection {
    let displayID: UInt32
    let displayFrame: CGRect // AppKit global points (bottom-left origin).
    let rect: CGRect
    let scale: CGFloat
}

struct AreaCaptureRequest {
    let displayID: UInt32
    let sourceRect: CGRect // Display-local points (top-left origin), snapped to pixels.
    let pixelWidth: Int
    let pixelHeight: Int
    let excludingBundleIdentifier: String
}

/// The OS seam: prefetch begins synchronously; all selection paths hide before pixels.
@MainActor protocol AreaCapturePlatform: AnyObject {
    func prefetchShareableContent()
    func selectArea() async -> AreaSelection?
    func hideSelection()
    func capture(_ request: AreaCaptureRequest, maximumBytes: Int) async throws -> Data
    func finishCapture()
}

@MainActor final class AreaCaptureSource: CapturePixelSource {
    private let platform: any AreaCapturePlatform
    private let bundleIdentifier: String
    init(platform: any AreaCapturePlatform, bundleIdentifier: String) {
        self.platform = platform
        self.bundleIdentifier = bundleIdentifier
    }

    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        platform.prefetchShareableContent()
        defer { platform.finishCapture() }
        let selection = await platform.selectArea()
        platform.hideSelection()
        guard let selection else { return .failure(.cancelled) }
        let clipped = selection.rect.intersection(selection.displayFrame)
        guard !clipped.isNull, !clipped.isEmpty, selection.scale > 0 else { return .failure(.emptyImage) }
        let scale = selection.scale
        let left = floor((clipped.minX - selection.displayFrame.minX) * scale)
        let top = floor((selection.displayFrame.maxY - clipped.maxY) * scale)
        let right = ceil((clipped.maxX - selection.displayFrame.minX) * scale)
        let bottom = ceil((selection.displayFrame.maxY - clipped.minY) * scale)
        let width = right - left, height = bottom - top
        // Bound the raw bitmap too, before asking the OS to allocate it.
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              width * height * 4 <= Double(maximumBytes) else { return .failure(.unavailable) }
        let request = AreaCaptureRequest(displayID: selection.displayID,
            sourceRect: CGRect(x: left / scale, y: top / scale, width: width / scale, height: height / scale),
            pixelWidth: Int(width), pixelHeight: Int(height), excludingBundleIdentifier: bundleIdentifier)
        do {
            let data = try await platform.capture(request, maximumBytes: maximumBytes)
            guard data.count <= maximumBytes else { return .failure(.unavailable) }
            return .success(CaptureImage(pngData: data))
        } catch {
            return .failure(.unavailable)
        }
    }
}
