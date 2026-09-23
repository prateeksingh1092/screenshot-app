import Foundation
import FrisketCore
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
}
