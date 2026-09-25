import AppKit
import FrisketCore
import QuartzCore

/// Coalesces Loupe samples so at most one small capture is in flight. Pointer moves that
/// arrive meanwhile collapse into the latest one; nothing is captured per move beyond that.
@MainActor final class LoupeFeed {
    typealias Capture = @MainActor (LoupeSample) async throws -> CGImage
    private let capture: Capture
    private let deliver: @MainActor (LoupeSample, CGImage) -> Void
    private var pending: LoupeSample?
    private var latest: LoupeSample?
    private var inFlight = false
    private var stopped = false

    init(capture: @escaping Capture, deliver: @escaping @MainActor (LoupeSample, CGImage) -> Void) {
        self.capture = capture
        self.deliver = deliver
    }

    func request(_ sample: LoupeSample) {
        guard !stopped, sample != latest || pending != nil else { return }
        latest = sample
        pending = sample
        if !inFlight { next() }
    }

    /// Drops the queued sample and any result still in flight.
    func stop() {
        stopped = true
        pending = nil
    }

    private func next() {
        guard !stopped, let sample = pending else { return }
        pending = nil
        inFlight = true
        Task { @MainActor [weak self, capture] in
            let image = try? await capture(sample)
            guard let self else { return }
            inFlight = false
            guard !stopped else { return }
            if let image { deliver(sample, image) }
            next()
        }
    }
}

/// The Loupe: device pixels around the pointer, one cell per pixel, the pointer's pixel
/// outlined. Layers only, so moving it never repaints the overlay beneath.
@MainActor final class LoupeView: NSView {
    static let cell: CGFloat = 8
    static let border: CGFloat = 2
    static var side: CGFloat { CGFloat(Loupe.span) * cell + border * 2 }

    private let pixels = CALayer()
    private let grid = CAShapeLayer()
    private let marker = CAShapeLayer()

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.side, height: Self.side))
        wantsLayer = true
        isHidden = true
        let layer = self.layer ?? CALayer()
        layer.backgroundColor = NSColor.black.cgColor
        layer.borderColor = NSColor.white.withAlphaComponent(0.8).cgColor
        layer.borderWidth = 1
        let inner = bounds.insetBy(dx: Self.border, dy: Self.border)
        pixels.frame = inner
        pixels.magnificationFilter = .nearest
        pixels.contentsGravity = .resize
        grid.frame = inner
        grid.fillColor = nil
        grid.strokeColor = NSColor.white.withAlphaComponent(0.2).cgColor
        grid.lineWidth = 0.5
        marker.fillColor = nil
        marker.strokeColor = NSColor.systemRed.cgColor
        marker.lineWidth = 2
        for sublayer in [pixels, grid, marker] { layer.addSublayer(sublayer) }
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Shows `image`, the pixels of `sample`, and outlines the pointer's pixel.
    func show(_ image: CGImage, of sample: LoupeSample) {
        let inner = bounds.insetBy(dx: Self.border, dy: Self.border)
        let cell = inner.width / CGFloat(sample.span)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pixels.contents = image
        let path = CGMutablePath()
        for index in 0...sample.span {
            let offset = CGFloat(index) * cell
            path.move(to: CGPoint(x: offset, y: 0)); path.addLine(to: CGPoint(x: offset, y: inner.height))
            path.move(to: CGPoint(x: 0, y: offset)); path.addLine(to: CGPoint(x: inner.width, y: offset))
        }
        grid.path = path
        // Rows count down from the top; this layer's origin is bottom-left.
        marker.path = CGPath(rect: CGRect(x: inner.minX + CGFloat(sample.column) * cell,
                                          y: inner.minY + CGFloat(sample.span - 1 - sample.row) * cell,
                                          width: cell, height: cell), transform: nil)
        CATransaction.commit()
        isHidden = false
    }

    /// Keeps the Loupe beside `pointer` (view-local points) and inside `bounds`.
    func place(beside pointer: CGPoint, in bounds: CGRect) {
        setFrameOrigin(Loupe.frame(size: frame.size, beside: pointer, in: bounds).origin)
    }

    func clear() {
        isHidden = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pixels.contents = nil
        CATransaction.commit()
    }
}
