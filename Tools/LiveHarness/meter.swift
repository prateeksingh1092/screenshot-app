// Pixel meters for live-harness evidence (Tools/LiveHarness/README.md). Reads PNGs only.
//
//   meter px FILE X Y [X Y …]        sRGB RGBA at each pixel
//   meter scan FILE [COL] [MARKCOL]  red/blue runs down COL and black marker runs down MARKCOL
//   meter redink FILE [BAND]         annotation-red pixels per BAND-row band (default 100)
//   meter band FILE START END        annotation-red pixels in rows START..<END
//   meter blocks FILE SCALE [MINHEIGHT]
//       Checks a scrolling capture of the pattern's --show-scroll page. Every complete block
//       must be 90 red + 90 blue rows (×SCALE) with its 8-row marker 164 rows below the block
//       top, blocks must be 400 rows apart, and the image must be at least MINHEIGHT rows.
//       Exit 0 when exact, 1 otherwise.
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
guard a.count >= 2 else { fputs("usage: meter px|scan|redink|band|blocks FILE …\n", stderr); exit(2) }
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
case "blocks":
    let scale = int(2), minHeight = int(3, 0)
    guard let column = bestColumn(img, isRed), let markColumn = bestColumn(img, isMarker) else {
        print("FAIL: no pattern blocks found"); exit(1)
    }
    let colour = runs(img, column: column) { isRed($0) ? "R" : isBlue($0) ? "B" : "." }
    let marks = runs(img, column: markColumn) { isMarker($0) ? "M" : "." }
    var problems: [String] = []
    if img.height < minHeight { problems.append("height \(img.height) < selected \(minHeight)") }
    // A block is complete when its red run doesn't touch the top edge and its blue run doesn't touch the bottom.
    var starts: [Int] = []
    for (i, run) in colour.enumerated() where run.kind == "R" && run.start > 0 {
        guard i + 1 < colour.count, colour[i + 1].kind == "B", colour[i + 1].start == run.start + run.length,
              colour[i + 1].start + colour[i + 1].length < img.height else { continue }
        starts.append(run.start)
        if run.length != 90 * scale { problems.append("block at \(run.start): red \(run.length) rows, expected \(90 * scale)") }
        if colour[i + 1].length != 90 * scale { problems.append("block at \(run.start): blue \(colour[i + 1].length) rows, expected \(90 * scale)") }
        let marker = marks.first { $0.start >= run.start && $0.start < run.start + 180 * scale }
        if marker?.start != run.start + 164 * scale || marker?.length != 8 * scale {
            problems.append("block at \(run.start): marker \(marker.map { "\($0.start)+\($0.length)" } ?? "missing"), expected \(run.start + 164 * scale)+\(8 * scale)")
        }
    }
    for (previous, next) in zip(starts, starts.dropFirst()) where next - previous != 400 * scale {
        problems.append("blocks at \(previous) and \(next) are \(next - previous) rows apart, expected \(400 * scale)")
    }
    if starts.isEmpty { problems.append("no complete block") }
    print("\(img.width)x\(img.height) complete blocks at \(starts)")
    if problems.isEmpty { print("PASS: every complete block is exact") } else { problems.forEach { print("FAIL: \($0)") }; exit(1) }
default:
    fputs("unknown meter \(a[0])\n", stderr); exit(2)
}
