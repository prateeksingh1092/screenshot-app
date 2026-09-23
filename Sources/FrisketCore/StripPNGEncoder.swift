import Foundation

/// Writes a PNG from top-to-bottom strips. Only the current strip and a small
/// pending IDAT buffer are retained besides the growing file.
public final class StripPNGEncoder {
    private let width: Int
    private var remaining: Int
    private var output = Data()
    private var pending = Data([0x78, 0x01])
    private var adler: UInt32 = 1
    private var failed = false

    public init?(width: Int, height: Int) {
        guard width > 0, height > 0, width <= Int.max / 4 / height else { return nil }
        self.width = width
        remaining = height
        output.append(contentsOf: [137, 80, 78, 71, 13, 10, 26, 10])
        writeChunk("IHDR", payload: ihdr(width: width, height: height))
    }

    public func append(_ strip: Bitmap) -> Bool {
        guard !failed, strip.width == width, strip.height > 0, strip.height <= remaining else {
            failed = true
            return false
        }
        for y in 0..<strip.height {
            var scanline = Data([0])
            let start = y * width * 4
            scanline.append(contentsOf: strip.bytes[start..<(start + width * 4)])
            appendStored(scanline, final: remaining - y == 1)
            adler = adler32(adler, scanline)
            flushPending(final: false)
        }
        remaining -= strip.height
        return true
    }

    public func finish() -> Data? {
        guard !failed, remaining == 0 else { return nil }
        var sum = adler.bigEndian
        pending.append(Swift.withUnsafeBytes(of: &sum) { Data($0) })
        flushPending(final: true)
        writeChunk("IEND", payload: Data())
        return output
    }

    private func appendStored(_ data: Data, final: Bool) {
        var index = data.startIndex
        while index < data.endIndex {
            let end = data.index(index, offsetBy: 65_535, limitedBy: data.endIndex) ?? data.endIndex
            let last = final && end == data.endIndex
            pending.append(last ? 1 : 0)
            let length = UInt16(end - index)
            var len = length.littleEndian
            var nlen = (~length).littleEndian
            pending.append(Swift.withUnsafeBytes(of: &len) { Data($0) })
            pending.append(Swift.withUnsafeBytes(of: &nlen) { Data($0) })
            pending.append(data[index..<end])
            index = end
        }
    }

    private func flushPending(final: Bool) {
        while pending.count >= 32_767 || (final && !pending.isEmpty) {
            let end = pending.index(pending.startIndex, offsetBy: 32_767, limitedBy: pending.endIndex) ?? pending.endIndex
            writeChunk("IDAT", payload: pending[pending.startIndex..<end])
            pending.removeSubrange(pending.startIndex..<end)
        }
    }

    private func writeChunk(_ type: String, payload: Data) {
        var length = UInt32(payload.count).bigEndian
        output.append(Swift.withUnsafeBytes(of: &length) { Data($0) })
        let typeBytes = Data(type.utf8)
        output.append(typeBytes)
        output.append(payload)
        var crc = crc32(typeBytes + payload).bigEndian
        output.append(Swift.withUnsafeBytes(of: &crc) { Data($0) })
    }
}

private func ihdr(width: Int, height: Int) -> Data {
    var data = Data()
    var w = UInt32(width).bigEndian
    var h = UInt32(height).bigEndian
    data.append(Swift.withUnsafeBytes(of: &w) { Data($0) })
    data.append(Swift.withUnsafeBytes(of: &h) { Data($0) })
    data.append(contentsOf: [8, 6, 0, 0, 0])
    return data
}

private func adler32(_ start: UInt32, _ data: Data) -> UInt32 {
    var s1 = start & 0xffff
    var s2 = start >> 16
    for byte in data {
        s1 = (s1 + UInt32(byte)) % 65521
        s2 = (s2 + s1) % 65521
    }
    return (s2 << 16) | s1
}

private func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffff_ffff
    for byte in data {
        crc = crc32Table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
    }
    return crc ^ 0xffff_ffff
}

private let crc32Table: [UInt32] = (0..<256).map { index in
    var crc = UInt32(index)
    for _ in 0..<8 {
        crc = crc & 1 == 1 ? 0xedb8_8320 ^ (crc >> 1) : crc >> 1
    }
    return crc
}
