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

    /// A Selection was made and frames are being sampled.
    var isRunning: Bool { request != nil && choice == nil }

    /// ⌘⇧6 pressed again during a scrolling capture means Done (DA-9).
    func finish() {
        guard isRunning else { return }
        choice = .done
    }

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

@MainActor private final class ScrollingKeysView: NSView {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn?()
        case 53: onEscape?()
        default: super.keyDown(with: event)
        }
    }
}

@MainActor private final class ScrollingKeyPanel: NSPanel {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn?()
        case 53: onEscape?()
        default: super.keyDown(with: event)
        }
    }
}

@MainActor private final class ScrollingSessionPanel: NSObject {
    private let panel: ScrollingKeyPanel
    private let imageView = NSImageView()
    private let status: NSTextField
    private let content = ScrollingKeysView(frame: NSRect(x: 0, y: 0, width: 280, height: 226))
    private let onDone: () -> Void
    private let onCancel: () -> Void

    init(done: @escaping () -> Void, cancel: @escaping () -> Void) {
        onDone = done
        onCancel = cancel
        panel = ScrollingKeyPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 226),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        status = NSTextField(wrappingLabelWithString: "Scroll the page yourself. Done keeps the image. Cancel discards it.")
        super.init()
        panel.onReturn = { [weak self] in self?.finish() }
        panel.onEscape = { [weak self] in self?.abort() }
        content.onReturn = { [weak self] in self?.finish() }
        content.onEscape = { [weak self] in self?.abort() }
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        imageView.frame = NSRect(x: 16, y: 112, width: 248, height: 98)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
        imageView.setAccessibilityLabel("Live scrolling preview")
        status.frame = NSRect(x: 16, y: 52, width: 248, height: 54)
        status.font = .systemFont(ofSize: 12)
        status.maximumNumberOfLines = 3
        let doneButton = NSButton(title: "Done", target: self, action: #selector(finish))
        doneButton.frame = NSRect(x: 16, y: 12, width: 120, height: 32)
        doneButton.bezelStyle = .push
        doneButton.setAccessibilityLabel("Done with scrolling capture")
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(abort))
        cancelButton.frame = NSRect(x: 144, y: 12, width: 120, height: 32)
        cancelButton.bezelStyle = .push
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
        panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 16, y: visible.maxY - panel.frame.height - 16))
        // DA-9 (D11): never take key, so Page Down, Space and arrows keep scrolling the page.
        // A click on the panel still makes it key, and then Esc and Return reach it.
        panel.orderFrontRegardless()
    }

    func close() { panel.close() }

    @objc private func finish() { onDone() }
    @objc private func abort() { onCancel() }
}
