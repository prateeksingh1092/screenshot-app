import Foundation

/// Writes a PNG from top-to-bottom strips. Only the current strip, the deflate
/// window, and the growing file are retained. IDAT bytes are one zlib stream
/// split across chunks, so repetitive screenshot rows stay small.
public final class StripPNGEncoder {
    private let width: Int
    private var remaining: Int
    private var output = Data()
    private var pending = Data()
    private var scanline: [UInt8]
    private var adler: UInt = 1
    private var stream = PNGDeflateStream()
    private var streamOpen = false
    private var failed = false
    private var chunkDestination = [UInt8](repeating: 0, count: 16_384)

    public init?(width: Int, height: Int) {
        let accepted = width > 0 && height > 0 && width <= Int.max / 4 / height
        let storedWidth = accepted ? width : 1
        self.width = storedWidth
        remaining = accepted ? height : 0
        scanline = [UInt8](repeating: 0, count: 1 + storedWidth * 4)
        guard accepted else { return nil }
        output.append(contentsOf: [137, 80, 78, 71, 13, 10, 26, 10])
        writeChunk("IHDR", payload: ihdr(width: width, height: height))
        guard pngDeflateInit(&stream, 0, 0x205) == 0 else { return nil }
        streamOpen = true
        // The linked deflate encoder emits raw deflate. PNG IDAT needs a zlib wrapper.
        pending.append(contentsOf: [0x78, 0x9c])
    }

    deinit {
        if streamOpen { _ = pngDeflateDestroy(&stream) }
    }

    public func append(_ strip: Bitmap) -> Bool {
        guard streamOpen, !failed, strip.width == width, strip.height > 0, strip.height <= remaining else {
            failed = true
            return false
        }
        for y in 0..<strip.height {
            let start = y * width * 4
            scanline.withUnsafeMutableBytes { destination in
                strip.bytes.withUnsafeBytes { source in
                    destination[0] = 0
                    memcpy(destination.baseAddress! + 1, source.baseAddress! + start, width * 4)
                }
            }
            let count = scanline.count
            adler = scanline.withUnsafeBytes { raw in
                zlibAdler32(adler, raw.bindMemory(to: UInt8.self).baseAddress, UInt32(count))
            }
            let accepted = scanline.withUnsafeBytes { raw -> Bool in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
                return compress(base, count: count, finalize: false)
            }
            guard accepted else {
                failed = true
                return false
            }
        }
        remaining -= strip.height
        return true
    }

    public func finish() -> Data? {
        guard streamOpen, !failed, remaining == 0 else { return nil }
        var trailer: UInt8 = 0
        guard compress(&trailer, count: 0, finalize: true) else { return nil }
        var sum = UInt32(truncatingIfNeeded: adler).bigEndian
        pending.append(Swift.withUnsafeBytes(of: &sum) { Data($0) })
        flushPending(final: true)
        writeChunk("IEND", payload: Data())
        _ = pngDeflateDestroy(&stream)
        streamOpen = false
        return output
    }

    private enum CompressStep {
        case error
        case end(Int)
        case ok(Int)
    }

    private func compress(_ bytes: UnsafePointer<UInt8>, count: Int, finalize: Bool) -> Bool {
        stream.source = bytes
        stream.sourceCount = count
        let flags: Int32 = finalize ? 1 : 0
        let capacity = chunkDestination.count
        var stalled = 0
        while true {
            let step = chunkDestination.withUnsafeMutableBytes { raw -> CompressStep in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return .error }
                stream.destination = base
                stream.destinationCount = capacity
                let status = pngDeflateProcess(&stream, flags)
                let written = capacity - stream.destinationCount
                if status == -1 { return .error }
                if status == 1 { return .end(written) }
                return .ok(written)
            }
            switch step {
            case .error:
                failed = true
                return false
            case let .end(written):
                if written > 0 {
                    pending.append(chunkDestination, count: written)
                    flushPending(final: false)
                }
                return true
            case let .ok(written):
                if written > 0 {
                    pending.append(chunkDestination, count: written)
                    flushPending(final: false)
                    stalled = 0
                } else {
                    stalled += 1
                    if stalled > 2 {
                        failed = true
                        return false
                    }
                }
                if stream.sourceCount == 0 && !finalize && written < capacity { return true }
            }
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
        var crc = UInt32(truncatingIfNeeded: pngCRC32(typeBytes, payload)).bigEndian
        output.append(Swift.withUnsafeBytes(of: &crc) { Data($0) })
    }
}

/// Layout matches the system deflate stream. Declared here so the memory-only
/// core does not import that framework.
private struct PNGDeflateStream {
    var destination: UnsafeMutablePointer<UInt8>? = nil
    var destinationCount = 0
    var source: UnsafePointer<UInt8>? = nil
    var sourceCount = 0
    var state: UnsafeMutableRawPointer? = nil
}

@_silgen_name("compression_stream_init")
private func pngDeflateInit(_ stream: UnsafeMutablePointer<PNGDeflateStream>, _ operation: Int32, _ algorithm: Int32) -> Int32

@_silgen_name("compression_stream_process")
private func pngDeflateProcess(_ stream: UnsafeMutablePointer<PNGDeflateStream>, _ flags: Int32) -> Int32

@_silgen_name("compression_stream_destroy")
private func pngDeflateDestroy(_ stream: UnsafeMutablePointer<PNGDeflateStream>) -> Int32

@_silgen_name("crc32")
private func zlibCRC32(_ crc: UInt, _ buffer: UnsafePointer<UInt8>?, _ length: UInt32) -> UInt

@_silgen_name("adler32")
private func zlibAdler32(_ adler: UInt, _ buffer: UnsafePointer<UInt8>?, _ length: UInt32) -> UInt

private func pngCRC32(_ type: Data, _ payload: Data) -> UInt {
    var crc = zlibCRC32(0, nil, 0)
    crc = type.withUnsafeBytes { raw in
        zlibCRC32(crc, raw.bindMemory(to: UInt8.self).baseAddress, UInt32(type.count))
    }
    return payload.withUnsafeBytes { raw in
        zlibCRC32(crc, raw.bindMemory(to: UInt8.self).baseAddress, UInt32(payload.count))
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

private extension Data {
    mutating func append(_ bytes: [UInt8], count: Int) {
        bytes.withUnsafeBytes { raw in
            append(contentsOf: raw.bindMemory(to: UInt8.self).prefix(count))
        }
    }
}
