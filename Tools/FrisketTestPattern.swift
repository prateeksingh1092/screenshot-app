// Synthetic-only manual fixture. Show modes launch windows only at the operator's request.
import AppKit
import ImageIO

@MainActor private final class PatternWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor private final class PatternView: NSView {
    override var acceptsFirstResponder: Bool { true }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }
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
        let caption = "Frisket synthetic pattern — move pointer here; Command-Shift-4, Return. Escape closes this pattern."
        caption.draw(at: CGPoint(x: 32, y: bounds.height - 70),
                     withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.white])
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSApp.terminate(nil) } else { super.keyDown(with: event) }
    }
}

/// The display to show patterns on: `--display ID|main|builtin|external`, else
/// `FRISKET_PATTERN_DISPLAY`, else the main display. ID is a CGDirectDisplayID.
@MainActor private func targetScreen(_ choice: String?) -> NSScreen? {
    func id(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    switch choice ?? ProcessInfo.processInfo.environment["FRISKET_PATTERN_DISPLAY"] ?? "main" {
    case "main": return NSScreen.main
    case "builtin": return NSScreen.screens.first { CGDisplayIsBuiltin(id($0)) != 0 }
    case "external": return NSScreen.screens.first { CGDisplayIsBuiltin(id($0)) == 0 }
    case let raw: return UInt32(raw).flatMap { want in NSScreen.screens.first { id($0) == want } }
    }
}

@main enum FrisketTestPattern {
    @MainActor static func main() {
        var args = CommandLine.arguments
        var display: String?
        if let flag = args.firstIndex(of: "--display"), flag + 1 < args.count {
            display = args[flag + 1]
            args.removeSubrange(flag...(flag + 1))
        }
        if args.count == 4, args[1] == "--verify", let scale = Int(args[3]), [1, 2].contains(scale) {
            do { try verify(path: args[2], scale: scale); print("PASS: dimensions, four sRGB quadrant pixels and black marker") }
            catch { fputs("FAIL: pasted PNG dimensions or marker pixels do not match the synthetic pattern\n", stderr); exit(1) }
            return
        }
        if args.count == 6, args[1] == "--verify-full",
           let width = Int(args[3]), let height = Int(args[4]),
           let scale = Int(args[5]), [1, 2].contains(scale),
           width >= 320 * scale, height >= 180 * scale {
            do {
                try verify(path: args[2], scale: scale, fullSize: (width, height))
                print("PASS: full display dimensions, four sRGB quadrant pixels and black marker")
            } catch {
                fputs("FAIL: full-display PNG dimensions or marker pixels do not match the synthetic pattern\n", stderr)
                exit(1)
            }
            return
        }
        if args.count == 4, args[1] == "--verify-redacted", let scale = Int(args[3]), [1, 2].contains(scale) {
            do {
                try verifyRedacted(path: args[2], scale: scale)
                print("PASS: red quadrant exactly opaque black, no red pixel anywhere, other quadrants and marker intact")
            } catch {
                fputs("FAIL: the red quadrant is not fully redacted, red remains, or other pattern pixels changed\n", stderr)
                exit(1)
            }
            return
        }
        guard args.count == 2, ["--show", "--show-all", "--show-full-screen", "--full-screen", "--show-window"].contains(args[1]) else {
            fputs("Usage: FrisketTestPattern --show | --show-all | --show-full-screen | --full-screen | --show-window [--display ID|main|builtin|external] | --verify /path/to/pasted.png 1|2 | --verify-full /path/to/pasted.png WIDTH HEIGHT 1|2 | --verify-redacted /path/to/image.png 1|2\n", stderr)
            exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let fullScreen = ["--show-full-screen", "--full-screen"].contains(args[1])
        let screens = args[1] == "--show-all" ? NSScreen.screens : targetScreen(display).map { [$0] } ?? []
        guard !screens.isEmpty else { exit(1) }
        let windowed = args[1] == "--show-window"
        // Two movable/minimizable synthetic windows for window-selection checks.
        let frames: [CGRect] = windowed ? [
            CGRect(x: screens[0].visibleFrame.minX + 80, y: screens[0].visibleFrame.minY + 80, width: 640, height: 400),
            CGRect(x: screens[0].visibleFrame.minX + 240, y: screens[0].visibleFrame.minY + 200, width: 640, height: 400)
        ] : screens.map(\.frame)
        let windows = frames.map { frame in
            let window = PatternWindow(contentRect: frame,
                styleMask: windowed ? [.titled, .closable, .miniaturizable, .resizable]
                    : fullScreen ? [.titled, .closable, .resizable] : [.borderless],
                backing: .buffered, defer: false)
            if fullScreen { window.collectionBehavior = [.fullScreenPrimary] }
            if windowed {
                // Keep the pattern centred in the entire captured frame, including
                // the titlebar, so the existing dimension/marker verifier applies.
                window.styleMask.insert(.fullSizeContentView)
                window.titlebarAppearsTransparent = true
                window.collectionBehavior.insert(.fullScreenPrimary)
            }
            window.colorSpace = .sRGB
            window.isReleasedWhenClosed = false
            window.title = "Frisket Synthetic Test Pattern"
            let view = PatternView(frame: CGRect(origin: .zero, size: window.frame.size))
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            return window
        }
        app.activate(ignoringOtherApps: true)
        if fullScreen { DispatchQueue.main.async { windows.first?.toggleFullScreen(nil) } }
        withExtendedLifetime(windows) { app.run() }
    }

    private enum Mismatch: Error { case image }
    private static func verify(path: String, scale: Int, fullSize: (width: Int, height: Int)? = nil) throws {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == (fullSize?.width ?? 320 * scale),
              image.height == (fullSize?.height ?? 180 * scale),
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
            let originX = (image.width - 320 * scale) / 2
            let originY = (image.height - 180 * scale) / 2
            for (x, y, expected) in samples {
                let offset = ((originY + y * scale) * image.width + originX + x * scale) * 4
                for channel in 0..<4 {
                    // Display color management can round channels by a few levels.
                    guard abs(Int(buffer[offset + channel]) - Int(expected[channel])) <= 3 else { throw Mismatch.image }
                }
            }
        }
    }

    /// For a 320×180-point pattern capture whose entire red quadrant was covered by Solid redaction.
    private static func verifyRedacted(path: String, scale: Int) throws {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == 320 * scale, image.height == 180 * scale,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw Mismatch.image }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { throw Mismatch.image }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        func pixel(_ x: Int, _ y: Int) -> [UInt8] { Array(pixels[((y * image.width + x) * 4)..<((y * image.width + x) * 4 + 4)]) }
        // Every covered pixel is exactly the fill at full opacity: no tolerance.
        for y in 0..<(90 * scale) { for x in 0..<(160 * scale) where pixel(x, y) != [0, 0, 0, 255] { throw Mismatch.image } }
        for y in 0..<image.height {
            for x in 0..<image.width {
                let value = pixel(x, y)
                if value[0] >= 252, value[1] <= 3, value[2] <= 3 { throw Mismatch.image }
            }
        }
        let intact: [(Int, Int, [UInt8])] = [(240, 30, [0, 255, 0, 255]), (40, 130, [0, 0, 255, 255]),
                                             (240, 130, [255, 255, 255, 255]), (12, 168, [0, 0, 0, 255])]
        for (x, y, expected) in intact {
            let value = pixel(x * scale, y * scale)
            for channel in 0..<4 where abs(Int(value[channel]) - Int(expected[channel])) > 3 { throw Mismatch.image }
        }
    }
}
