// sheet OUT COLS FILE…: a labelled contact sheet of evidence PNGs, for a run report.
import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 3, let columns = Int(arguments[1]), columns > 0 else {
    fputs("usage: sheet OUT COLS FILE…\n", stderr); exit(2)
}
let files = Array(arguments.dropFirst(2))
let images = files.compactMap { NSImage(contentsOfFile: $0) }
guard !images.isEmpty, images.count == files.count else { fputs("cannot read every input\n", stderr); exit(2) }
let cellWidth = images.map(\.size.width).max()!, cellHeight = images.map(\.size.height).max()!
let rows = (images.count + columns - 1) / columns
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(cellWidth) * columns, pixelsHigh: Int(cellHeight + 20) * rows,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.gray.setFill()
NSRect(x: 0, y: 0, width: cellWidth * CGFloat(columns), height: (cellHeight + 20) * CGFloat(rows)).fill()
for (index, image) in images.enumerated() {
    let column = index % columns, row = rows - 1 - index / columns
    image.draw(in: NSRect(x: CGFloat(column) * cellWidth, y: CGFloat(row) * (cellHeight + 20), width: image.size.width, height: image.size.height))
    (URL(fileURLWithPath: files[index]).lastPathComponent as NSString).draw(
        at: NSPoint(x: CGFloat(column) * cellWidth + 4, y: CGFloat(row) * (cellHeight + 20) + cellHeight + 2),
        withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12)])
}
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { fputs("cannot encode\n", stderr); exit(1) }
try png.write(to: URL(fileURLWithPath: arguments[0]))
