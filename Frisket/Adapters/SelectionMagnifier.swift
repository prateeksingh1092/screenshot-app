import AppKit
@preconcurrency import ScreenCaptureKit
import CoreVideo

/// A bounded, memory-only preview sampled before the selection panel is shown.
/// No timer, live screen stream, event monitor, or disk cache is retained.
@MainActor struct SelectionMagnifier {
    private let image: CGImage
    private let scale: CGFloat

    static func prepare(on screen: NSScreen, content: SCShareableContent,
                        excluding bundleIdentifier: String,
                        additionalExclusions: Set<String> = []) async throws -> SelectionMagnifier {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else {
            throw PreviewError.unavailable
        }
        let scale = screen.backingScaleFactor
        let width = screen.frame.width * scale, height = screen.frame.height * scale
        guard width > 0, height > 0, width * height * 4 <= 128 * 1024 * 1024 else {
            throw PreviewError.unavailable
        }
        let filter = try ScreenCapturePolicy.filter(display: display, content: content, excluding: bundleIdentifier,
                                                    additionalExclusions: additionalExclusions)
        let configuration = ScreenCapturePolicy.configuration(sourceRect: CGRect(origin: .zero, size: screen.frame.size),
                                                              pixelWidth: Int(width), pixelHeight: Int(height))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard image.width == Int(width), image.height == Int(height) else { throw PreviewError.unavailable }
        return SelectionMagnifier(image: image, scale: scale)
    }

    func draw(at pointer: CGPoint, in bounds: CGRect) {
        // CGImage crops have a top-left origin; overlay points have a bottom-left origin.
        let pixelX = min(max(Int(floor(pointer.x * scale)), 0), image.width - 1)
        let pixelY = min(max(Int(floor((bounds.height - pointer.y) * scale)), 0), image.height - 1)
        let columns = min(15, image.width), rows = min(15, image.height)
        let left = min(max(pixelX - columns / 2, 0), image.width - columns)
        let top = min(max(pixelY - rows / 2, 0), image.height - rows)
        guard let sample = image.cropping(to: CGRect(x: left, y: top, width: columns, height: rows)) else { return }
        let cell: CGFloat = 8
        let size = CGSize(width: CGFloat(columns) * cell, height: CGFloat(rows) * cell)
        let x = pointer.x + 22 + size.width <= bounds.maxX ? pointer.x + 22 : pointer.x - 22 - size.width
        let y = pointer.y + 22 + size.height + 22 <= bounds.maxY ? pointer.y + 22 : pointer.y - 22 - size.height - 22
        let destination = CGRect(x: max(0, min(x, bounds.maxX - size.width)),
                                 y: max(0, min(y, bounds.maxY - size.height - 22)),
                                 width: size.width, height: size.height)
        NSColor.black.setFill()
        CGRect(x: destination.minX - 2, y: destination.minY - 2,
               width: size.width + 4, height: size.height + 24).fill()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: sample, size: CGSize(width: columns, height: rows))
            .draw(in: destination, from: .zero, operation: .copy, fraction: 1)
        NSColor.white.withAlphaComponent(0.25).setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 0.5
        for column in 0...columns {
            let x = destination.minX + CGFloat(column) * cell
            grid.move(to: CGPoint(x: x, y: destination.minY))
            grid.line(to: CGPoint(x: x, y: destination.maxY))
        }
        for row in 0...rows {
            let y = destination.minY + CGFloat(row) * cell
            grid.move(to: CGPoint(x: destination.minX, y: y))
            grid.line(to: CGPoint(x: destination.maxX, y: y))
        }
        grid.stroke()
        NSColor.systemRed.setStroke()
        let marker = NSBezierPath(rect: CGRect(x: destination.minX + CGFloat(pixelX - left) * cell,
            y: destination.minY + CGFloat(rows - 1 - (pixelY - top)) * cell, width: cell, height: cell))
        marker.lineWidth = 2
        marker.stroke()
        NSGraphicsContext.restoreGraphicsState()
        "Pixels under the pointer".draw(at: CGPoint(x: destination.minX + 3, y: destination.maxY + 4),
            withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.white])
    }

    private enum PreviewError: Error { case unavailable }
}
