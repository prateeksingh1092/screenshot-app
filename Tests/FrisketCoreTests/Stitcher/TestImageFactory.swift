import CoreGraphics
import Foundation

/// Synthetic pages for scrolling tests. A frame is a window into one tall document,
/// so two offsets that share rows are the same pixels.
enum TestImageFactory {
    static func solidColor(width: Int, height: Int, red: UInt8 = 128, green: UInt8 = 128,
                           blue: UInt8 = 128, alpha: UInt8 = 255) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = red
            pixels[index + 1] = green
            pixels[index + 2] = blue
            pixels[index + 3] = alpha
        }
        return image(width: width, height: height, pixels: pixels)
    }

    static func repeatedScrollingFrame(width: Int, height: Int, logicalYOffset: Int, period: Int = 48) -> CGImage? {
        _ = period
        return scrollingFrame(width: width, height: height, logicalYOffset: logicalYOffset)
    }

    static func scrollingFrame(width: Int, height: Int, logicalYOffset: Int = 0) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let logicalY = logicalYOffset + y
            for x in 0..<width {
                let index = (y * width + x) * 4
                pixels[index] = UInt8(truncatingIfNeeded: logicalY &* 13 &+ x)
                pixels[index + 1] = UInt8(truncatingIfNeeded: logicalY &* 29 &+ 7)
                pixels[index + 2] = UInt8(truncatingIfNeeded: logicalY &* 53 &+ x &* 3)
                pixels[index + 3] = 255
            }
        }
        return image(width: width, height: height, pixels: pixels)
    }

    private static func image(width: Int, height: Int, pixels: [UInt8]) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
