// Synthetic-only manual fixture. --show launches a window only when the operator requests it.
import AppKit
import ImageIO

@MainActor private final class PatternWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor private final class PatternView: NSView {
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.15, green: 0.15, blue: 0.15, alpha: 1).setFill()
        bounds.fill()
        let region = CGRect(x: (bounds.width - 320) / 2, y: (bounds.height - 180) / 2, width: 320, height: 180)
        let quadrants: [(CGFloat, CGFloat, NSColor)] = [
            (0, 90, NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)),
            (160, 90, NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)),
            (0, 0, NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)),
            (160, 0, NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ]
        for (x, y, color) in quadrants {
            color.setFill()
            CGRect(x: region.minX + x, y: region.minY + y, width: 160, height: 90).fill()
        }
        NSColor.black.setFill()
        CGRect(x: region.minX + 8, y: region.minY + 8, width: 8, height: 8).fill()
        let caption = "Frisket synthetic pattern — move pointer here; ⌃⌥⌘4, Return. Escape closes this pattern."
        caption.draw(at: CGPoint(x: 32, y: bounds.height - 70),
                     withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.white])
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSApp.terminate(nil) } else { super.keyDown(with: event) }
    }
}

@main enum FrisketTestPattern {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.count == 4, args[1] == "--verify", let scale = Int(args[3]), [1, 2].contains(scale) {
            do { try verify(path: args[2], scale: scale); print("PASS: dimensions, four sRGB quadrant pixels and black marker") }
            catch { fputs("FAIL: pasted PNG dimensions or marker pixels do not match the synthetic pattern\n", stderr); exit(1) }
            return
        }
        guard args.count == 2, args[1] == "--show" else {
            fputs("Usage: FrisketTestPattern --show | --verify /path/to/pasted.png 1|2\n", stderr)
            exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        guard let screen = NSScreen.main else { exit(1) }
        let window = PatternWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.colorSpace = .sRGB
        window.isReleasedWhenClosed = false
        window.title = "Frisket Synthetic Test Pattern"
        let view = PatternView(frame: CGRect(origin: .zero, size: screen.frame.size))
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        app.activate(ignoringOtherApps: true)
        withExtendedLifetime(window) { app.run() }
    }

    private enum Mismatch: Error { case image }
    private static func verify(path: String, scale: Int) throws {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == 320 * scale, image.height == 180 * scale,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw Mismatch.image }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { throw Mismatch.image }
            // CGImage row zero is the top row in this untransformed bitmap context.
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let samples: [(Int, Int, [UInt8])] = [
                (40, 30, [255, 0, 0, 255]), (240, 30, [0, 255, 0, 255]),
                (40, 130, [0, 0, 255, 255]), (240, 130, [255, 255, 255, 255]),
                (12, 168, [0, 0, 0, 255])
            ]
            let buffer = bytes.bindMemory(to: UInt8.self)
            for (x, y, expected) in samples {
                let offset = ((y * scale) * image.width + x * scale) * 4
                for channel in 0..<4 {
                    // Display color management can round channels by a few levels.
                    guard abs(Int(buffer[offset + channel]) - Int(expected[channel])) <= 3 else { throw Mismatch.image }
                }
            }
        }
    }
}
