import CoreGraphics
import FrisketCore
import Testing

/// D9 (story 90): fixed-size Thumbnails stack without overlapping.
struct ThumbnailStackLayoutTests {
    private let size = ThumbnailStackLayout.cardSize
    private let builtin = CGRect(x: 0, y: 80, width: 1792, height: 1015)     // this Mac's visible frame, Dock at the bottom
    private let external = CGRect(x: 1792, y: 0, width: 1920, height: 1055)

    @Test(arguments: [1, 2, 3, 4])
    func upToTheStackLimitThumbnailsNeverOverlap(count: Int) {
        for frame in [builtin, external] {
            let rects = ThumbnailStackLayout.origins(count: count, in: frame).map { CGRect(origin: $0, size: size) }
            #expect(rects.count == count)
            for (i, a) in rects.enumerated() {
                #expect(frame.contains(a), "Thumbnail \(i) leaves the visible frame")
                for b in rects[(i + 1)...] { #expect(!a.intersects(b), "Thumbnails \(a) and \(b) overlap") }
            }
        }
    }

    @Test func newestSitsInTheBottomRightCornerAndOlderOnesStackUpward() {
        let origins = ThumbnailStackLayout.origins(count: 3, in: external)
        #expect(origins[0] == CGPoint(x: external.maxX - 20 - size.width, y: external.minY + 20))
        #expect(origins[1].y - origins[0].y == size.height + ThumbnailStackLayout.gap)
        #expect(Set(origins.map(\.x)).count == 1)
    }

    @Test func removingOneClosesTheGap() {
        let three = ThumbnailStackLayout.origins(count: 3, in: builtin)
        let two = ThumbnailStackLayout.origins(count: 2, in: builtin)
        #expect(two == Array(three.prefix(2)))
    }

    @Test func onlyADisplayTooShortForTheStackCompressesIt() {
        let short = CGRect(x: 0, y: 0, width: 1280, height: 600)
        let origins = ThumbnailStackLayout.origins(count: 4, in: short)
        #expect(origins.last.map { $0.y + size.height } ?? 0 <= short.maxY - 20)
    }
}
