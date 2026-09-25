// Pixel meters for live-harness evidence (Tools/LiveHarness/README.md). Reads PNGs only.
//
//   meter px FILE X Y [X Y …]        sRGB RGBA at each pixel
//   meter scan FILE [COL] [MARKCOL]  red/blue runs down COL and black marker runs down MARKCOL
//   meter redink FILE [BAND]         annotation-red pixels per BAND-row band (default 100)
//   meter band FILE START END        annotation-red pixels in rows START..<END
//   meter colour FILE RRGGBB [X0 Y0 X1 Y1]  pixels within 8 per channel of RRGGBB (in the rect, else the image)
import CoreGraphics
import Foundation
import ImageIO

struct Image {
    let width: Int, height: Int, bytes: [UInt8]
    init(_ path: String) {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { fputs("cannot read \(path)\n", stderr); exit(2) }
        width = image.width; height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        bytes = buffer
    }
    func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) { let o = (y * width + x) * 4; return (Int(bytes[o]), Int(bytes[o + 1]), Int(bytes[o + 2])) }
    func rgba(_ x: Int, _ y: Int) -> [Int] { let o = (y * width + x) * 4; return (0..<4).map { Int(bytes[o + $0]) } }
}

func isRed(_ c: (Int, Int, Int)) -> Bool { c.0 > 180 && c.1 < 110 && c.2 < 110 }
func isBlue(_ c: (Int, Int, Int)) -> Bool { c.2 > 180 && c.0 < 120 && c.1 < 140 }
func isMarker(_ c: (Int, Int, Int)) -> Bool { c.0 < 30 && c.1 < 30 && c.2 < 30 }
/// Frisket's annotation red (strong red with a little blue), as distinct from the pattern's pure red.
func isInk(_ c: (Int, Int, Int)) -> Bool { c.0 > 200 && c.1 < 80 && c.2 > 20 && c.2 < 110 }

struct Run { let kind: Character; let start: Int; let length: Int }
func runs(_ img: Image, column: Int, classify: ((Int, Int, Int)) -> Character) -> [Run] {
    var out: [Run] = []; var current: Character = "."; var start = 0
    for y in 0..<img.height {
        let k = classify(img.rgb(column, y))
        if k != current { if current != "." { out.append(Run(kind: current, start: start, length: y - start)) }; current = k; start = y }
    }
    if current != "." { out.append(Run(kind: current, start: start, length: img.height - start)) }
    return out
}
/// The column with the most pixels matching `test`, so callers need not know where the selection began.
func bestColumn(_ img: Image, _ test: ((Int, Int, Int)) -> Bool) -> Int? {
    var best: (column: Int, count: Int)?
    for x in 0..<img.width {
        var n = 0
        for y in 0..<img.height where test(img.rgb(x, y)) { n += 1 }
        if n > 0, n > (best?.count ?? 0) { best = (x, n) }
    }
    return best?.column
}

let a = Array(CommandLine.arguments.dropFirst())
guard a.count >= 2 else { fputs("usage: meter px|scan|redink|band|colour FILE …\n", stderr); exit(2) }
let img = Image(a[1])
func int(_ i: Int, _ fallback: Int? = nil) -> Int {
    if i < a.count, let v = Int(a[i]) { return v }
    if let fallback { return fallback }
    fputs("bad argument \(i)\n", stderr); exit(2)
}

switch a[0] {
case "px":
    var i = 2
    while i + 1 < a.count { let x = int(i), y = int(i + 1); print("(\(x),\(y)) sRGB=\(img.rgba(x, y))"); i += 2 }
case "scan":
    let column = int(2, bestColumn(img, isRed) ?? 0), markColumn = int(3, bestColumn(img, isMarker) ?? 0)
    let colour = runs(img, column: column) { isRed($0) ? "R" : isBlue($0) ? "B" : "." }
    let marks = runs(img, column: markColumn) { isMarker($0) ? "M" : "." }
    print("\(img.width)x\(img.height) col=\(column) runs:", colour.map { "\($0.kind)@\($0.start)+\($0.length)" }.joined(separator: " "),
          " markcol=\(markColumn) markers:", marks.map { "\($0.start)+\($0.length)" }.joined(separator: " "))
case "redink":
    let band = int(2, 100)
    var bands = [Int](repeating: 0, count: img.height / band + 1)
    for y in 0..<img.height { for x in 0..<img.width where isInk(img.rgb(x, y)) { bands[y / band] += 1 } }
    print("\(img.width)x\(img.height) annotation-red px per \(band)-row band:", bands)
case "band":
    let start = max(0, int(2)), end = min(img.height, int(3))
    var n = 0
    for y in start..<max(start, end) { for x in 0..<img.width where isInk(img.rgb(x, y)) { n += 1 } }
    print(n)
case "colour":
    guard let value = UInt32(a.count > 2 ? a[2] : "", radix: 16) else { fputs("bad colour\n", stderr); exit(2) }
    let want = (Int(value >> 16 & 0xff), Int(value >> 8 & 0xff), Int(value & 0xff))
    let x0 = max(0, int(3, 0)), y0 = max(0, int(4, 0)), x1 = min(img.width, int(5, img.width)), y1 = min(img.height, int(6, img.height))
    var n = 0
    for y in y0..<max(y0, y1) {
        for x in x0..<max(x0, x1) {
            let c = img.rgb(x, y)
            if abs(c.0 - want.0) <= 8, abs(c.1 - want.1) <= 8, abs(c.2 - want.2) <= 8 { n += 1 }
        }
    }
    print(n)
default:
    fputs("unknown meter \(a[0])\n", stderr); exit(2)
}
