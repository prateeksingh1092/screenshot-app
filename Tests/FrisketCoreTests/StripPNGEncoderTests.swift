import CoreGraphics
import Foundation
import FrisketCore
import ImageIO
import Testing

@Suite struct StripPNGEncoderTests {
    @Test func stripEncoderWritesAPNGSignatureAndIHDR() throws {
        let row = try #require(Bitmap(width: 2, height: 1, pixels: [
            RGBAPixel(red: 1, green: 2, blue: 3, alpha: 255),
            RGBAPixel(red: 4, green: 5, blue: 6, alpha: 255)
        ]))
        let encoder = try #require(StripPNGEncoder(width: 2, height: 2))
        #expect(encoder.append(row))
        #expect(encoder.append(row))
        let png = try #require(encoder.finish())
        #expect(png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
        #expect(png.count > 33)
    }

    @Test func repetitiveStripsCompressAndRoundTrip() throws {
        let pixel = RGBAPixel(red: 10, green: 20, blue: 30, alpha: 255)
        let row = try #require(Bitmap(width: 64, height: 16, pixels: Array(repeating: pixel, count: 64 * 16)))
        let encoder = try #require(StripPNGEncoder(width: 64, height: 64))
        for _ in 0..<4 { #expect(encoder.append(row)) }
        let png = try #require(encoder.finish())
        #expect(png.count < 64 * 64 * 4)
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 64)
        #expect(image.height == 64)
        var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
        let drew = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 64, height: 64, bitsPerComponent: 8,
                                          bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            return true
        }
        #expect(drew)
        #expect(bytes[0] == 10 && bytes[1] == 20 && bytes[2] == 30 && bytes[3] == 255)
        #expect(bytes[bytes.count - 4] == 10 && bytes[bytes.count - 1] == 255)
    }

    @Test func variedStripsRoundTripAcrossIDATChunks() throws {
        let width = 180
        let stripHeight = 48
        var pixels: [RGBAPixel] = []
        pixels.reserveCapacity(width * stripHeight)
        for index in 0..<(width * stripHeight) {
            pixels.append(RGBAPixel(red: UInt8(truncatingIfNeeded: index &* 17),
                                    green: UInt8(truncatingIfNeeded: index &* 31),
                                    blue: UInt8(truncatingIfNeeded: index &* 13),
                                    alpha: 255))
        }
        let strip = try #require(Bitmap(width: width, height: stripHeight, pixels: pixels))
        let encoder = try #require(StripPNGEncoder(width: width, height: stripHeight * 2))
        #expect(encoder.append(strip))
        #expect(encoder.append(strip))
        let png = try #require(encoder.finish())
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = [UInt8](repeating: 0, count: width * stripHeight * 2 * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drew = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: stripHeight * 2,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: stripHeight * 2))
            return true
        }
        #expect(drew)
        #expect(bytes[0] == pixels[0].red && bytes[1] == pixels[0].green && bytes[2] == pixels[0].blue)
        let last = pixels.count - 1
        let tail = bytes.count - 4
        #expect(bytes[tail] == pixels[last].red && bytes[tail + 1] == pixels[last].green && bytes[tail + 2] == pixels[last].blue)
    }
}
