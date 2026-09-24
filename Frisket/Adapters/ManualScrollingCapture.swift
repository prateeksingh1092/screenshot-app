import AppKit
import CoreGraphics
import FrisketCore

/// The existing ScreenCaptureKit region path. Scrolling capture samples it; it does not add a capture API.
@MainActor protocol ScrollingRegionCapturing: AnyObject {
    func prefetchShareableContent() async throws
    /// Same preparation area capture uses. Selection refuses to appear without it.
    func prepareSelection() async
    func selectArea() async -> AreaSelection?
    func hideSelection()
    func finishCapture()
    func captureRegion(_ request: AreaCaptureRequest) async throws -> CGImage
}

/// Manual scrolling. The person moves the page; this only samples the selected region and shows Done or Cancel.
@MainActor final class ManualScrollingCapture: ScrollingFrameFeed, ScrollingPreviewSurface {
    private let platform: any ScrollingRegionCapturing
    private let bundleIdentifier: String
    private var request: AreaCaptureRequest?
    private var choice: ScrollingFrameEvent?
    private var panel: ScrollingSessionPanel?
    private var prepared = false
    private var sampled = false

    init(platform: any ScrollingRegionCapturing, bundleIdentifier: String) {
        self.platform = platform
        self.bundleIdentifier = bundleIdentifier
    }

    func hide() {
        panel?.close()
        panel = nil
        choice = nil
        request = nil
        prepared = false
        sampled = false
        platform.finishCapture()
    }

    /// The panel and adapter tests use the same cancellation action.
    func cancel() { choice = .cancel }

    func nextFrame() async -> ScrollingFrameEvent {
        if let choice { return choice }
        if !prepared {
            prepared = true
            do { try await platform.prefetchShareableContent() }
            catch let failure as CaptureSourceFailure { return .failed(failure) }
            catch { return .failed(.unavailable) }
            await platform.prepareSelection()
            let selection = await platform.selectArea()
            platform.hideSelection()
            guard let selection, let request = regionRequest(for: selection) else { return .cancel }
            self.request = request
        }
        guard let request else { return .cancel }
        if sampled {
            try? await Task.sleep(for: .milliseconds(250))
            if let choice { return choice }
        }
        do {
            let image = try await platform.captureRegion(request)
            if let choice { return choice }
            guard let viewport = ScrollingViewport(cgImage: image) else { return .failed(.unavailable) }
            sampled = true
            return .viewport(viewport)
        } catch let failure as CaptureSourceFailure {
            if let choice { return choice }
            return .failed(failure)
        } catch {
            if let choice { return choice }
            return .failed(.unavailable)
        }
    }

    func update(_ preview: ScrollingPreview) async {
        if panel == nil {
            panel = ScrollingSessionPanel(done: { [weak self] in self?.choice = .done },
                                          cancel: { [weak self] in self?.cancel() })
        }
        panel?.update(preview)
    }

    private func regionRequest(for selection: AreaSelection) -> AreaCaptureRequest? {
        let clipped = selection.rect.intersection(selection.displayFrame)
        guard !clipped.isNull, !clipped.isEmpty, selection.scale > 0 else { return nil }
        let scale = selection.scale
        let left = floor((clipped.minX - selection.displayFrame.minX) * scale)
        let top = floor((selection.displayFrame.maxY - clipped.maxY) * scale)
        let right = ceil((clipped.maxX - selection.displayFrame.minX) * scale)
        let bottom = ceil((selection.displayFrame.maxY - clipped.minY) * scale)
        let width = right - left, height = bottom - top
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              width * height <= Double(ScrollingCaptureBudget.v1.pixelCap),
              width * height * 4 <= Double(ScrollingCaptureBudget.v1.memoryBudgetBytes) else { return nil }
        return AreaCaptureRequest(displayID: selection.displayID,
            sourceRect: CGRect(x: left / scale, y: top / scale, width: width / scale, height: height / scale),
            pixelWidth: Int(width), pixelHeight: Int(height), excludingBundleIdentifier: bundleIdentifier)
    }
}

@MainActor private final class ScrollingSessionPanel: NSObject {
    private let panel: NSPanel
    private let imageView = NSImageView()
    private let status: NSTextField
    private let onDone: () -> Void
    private let onCancel: () -> Void

    init(done: @escaping () -> Void, cancel: @escaping () -> Void) {
        onDone = done
        onCancel = cancel
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 250),
                        styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        status = NSTextField(wrappingLabelWithString: "Scroll the page yourself. Done keeps the image. Cancel discards it.")
        super.init()
        panel.title = "Scrolling capture"
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 250))
        imageView.frame = NSRect(x: 20, y: 96, width: 240, height: 110)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityLabel("Live scrolling preview")
        status.frame = NSRect(x: 16, y: 56, width: 248, height: 36)
        status.font = .systemFont(ofSize: 11)
        let doneButton = NSButton(title: "Done", target: self, action: #selector(finish))
        doneButton.frame = NSRect(x: 16, y: 16, width: 120, height: 32)
        doneButton.bezelStyle = .rounded
        doneButton.setAccessibilityLabel("Done with scrolling capture")
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(abort))
        cancelButton.frame = NSRect(x: 144, y: 16, width: 120, height: 32)
        cancelButton.bezelStyle = .rounded
        cancelButton.setAccessibilityLabel("Cancel scrolling capture")
        content.addSubview(imageView)
        content.addSubview(status)
        content.addSubview(doneButton)
        content.addSubview(cancelButton)
        panel.contentView = content
    }

    func update(_ preview: ScrollingPreview) {
        if let image = NSImage(data: preview.pngData) { imageView.image = image }
        if let notice = preview.notice { status.stringValue = notice.message }
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 24, y: visible.maxY - panel.frame.height - 24))
        panel.orderFrontRegardless()
    }

    func close() { panel.close() }

    @objc private func finish() { onDone() }
    @objc private func abort() { onCancel() }
}
