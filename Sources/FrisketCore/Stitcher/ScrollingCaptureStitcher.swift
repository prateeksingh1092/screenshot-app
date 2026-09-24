import CoreGraphics
import Foundation

/// How successive viewports were joined. Downward scrolling appends from the bottom.
nonisolated enum ScrollingCaptureMergeDirection {
    case unresolved
    case appendFromBottom
    case appendFromTop
}

nonisolated enum ScrollingCaptureStitchOutcome {
    case initialized
    case appended(deltaY: Int)
    case ignoredNoMovement
    case ignoredAlignmentFailed
    case reachedHeightLimit
}

nonisolated enum ScrollingCaptureStitchSafety: Equatable {
    case confirmed
    case tentative(reason: String)
    case unsafe(reason: String)

    var isUnsafe: Bool {
        if case .unsafe = self { return true }
        return false
    }
}

nonisolated enum ScrollingCaptureAlignmentPath: String {
    case initialFrame = "initial-frame"
    case fastGuided = "fast-guided"
    case guidedVision = "guided-vision"
    case recoveryVision = "recovery-vision"
    case noMovement = "no-movement"
    case duplicateBoundary = "duplicate-boundary"
    case alignmentFailed = "alignment-failed"
    case heightLimit = "height-limit"
}

nonisolated struct ScrollingCaptureAlignmentDebugInfo {
    let path: ScrollingCaptureAlignmentPath
    let usedVisionEstimate: Bool
    let confidence: Double
    let pixelScore: Double?
    let totalScore: Double?
    let appendDeltaY: Int?
    let visionAgreementCount: Int
}

nonisolated struct ScrollingCaptureStitchUpdate {
    let outcome: ScrollingCaptureStitchOutcome
    let mergedImage: CGImage?
    let acceptedFrameCount: Int
    let outputHeight: Int
    let matchFailureCount: Int
    let mergeDirection: ScrollingCaptureMergeDirection
    let likelyReachedBoundary: Bool
    let safety: ScrollingCaptureStitchSafety
    let alignmentDebug: ScrollingCaptureAlignmentDebugInfo?
}

/// Joins same-size viewports into a tall page. Static bands that repeat at the
/// top or bottom are removed once movement is confirmed. Output is stored as
/// 256-row strips so a long page does not stay as one bitmap.
nonisolated final class ScrollingCaptureStitcher: @unchecked Sendable {
    private struct Strip {
        let rowCount: Int
        let payload: Data
        let compressed: Bool

        init(rows: Data, rowCount: Int) {
            self.rowCount = rowCount
            if let packed = try? (rows as NSData).compressed(using: .lzfse) {
                payload = packed as Data
                compressed = true
            } else {
                payload = rows
                compressed = false
            }
        }

        func rows() -> Data? {
            if !compressed { return payload }
            return (try? (payload as NSData).decompressed(using: .lzfse)) as Data?
        }
    }

    private final class StripReader {
        let strips: [Strip]
        let bytesPerRow: Int
        let byteCount: Int
        private let lock = NSLock()
        private var cached = -1
        private var cachedRows = Data()

        init(strips: [Strip], bytesPerRow: Int) {
            self.strips = strips
            self.bytesPerRow = bytesPerRow
            byteCount = strips.reduce(0) { $0 + $1.rowCount * bytesPerRow }
        }

        func read(into buffer: UnsafeMutableRawPointer, position: Int, count: Int) -> Int {
            guard position >= 0, count > 0, position < byteCount else { return 0 }
            let available = min(count, byteCount - position)
            var copied = 0
            lock.lock()
            defer { lock.unlock() }
            while copied < available {
                var origin = 0
                var index = 0
                while index < strips.count {
                    let size = strips[index].rowCount * bytesPerRow
                    if position + copied < origin + size { break }
                    origin += size
                    index += 1
                }
                guard index < strips.count else { break }
                if cached != index {
                    guard let rows = strips[index].rows() else { return copied }
                    cachedRows = rows
                    cached = index
                }
                let local = position + copied - origin
                let piece = min(available - copied, cachedRows.count - local)
                cachedRows.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    buffer.advanced(by: copied).copyMemory(from: base.advanced(by: local), byteCount: piece)
                }
                copied += piece
            }
            return copied
        }
    }

    private var width = 0
    private var viewport: [UInt8] = []
    private var viewportHeight = 0
    private var strips: [Strip] = []
    private var headerRows = 0
    private var footerRows = 0
    private var trimmedBands = false
    private var direction: ScrollingCaptureMergeDirection = .unresolved
    private var cachedPage: CGImage?
    private var failures = 0
    private(set) var acceptedFrameCount = 0

    var outputHeight: Int { strips.reduce(0) { $0 + $1.rowCount } }
    var pixelWidth: Int { width }
    var retainedByteCount: Int { strips.reduce(0) { $0 + $1.payload.count } + viewport.count }

    func start(with image: CGImage) -> ScrollingCaptureStitchUpdate? {
        guard let pixels = copiedPixels(image), image.width > 0, image.height > 0 else { return nil }
        width = image.width
        viewport = pixels
        viewportHeight = image.height
        strips = []
        headerRows = 0
        footerRows = 0
        trimmedBands = false
        direction = .unresolved
        cachedPage = nil
        failures = 0
        acceptedFrameCount = 1
        store(pixels, rows: image.height)
        return update(outcome: .initialized, path: .initialFrame, confidence: 1, includePage: true)
    }

    func append(
        _ image: CGImage,
        maxOutputHeight: Int,
        expectedSignedDeltaPixels: Int? = nil,
        renderMergedImage: Bool = true,
        allowsSettledPartialStep: Bool = false
    ) -> ScrollingCaptureStitchUpdate? {
        guard !viewport.isEmpty else { return start(with: image) }
        guard image.width == width, image.height == viewportHeight, let next = copiedPixels(image) else {
            failures += 1
            return update(outcome: .ignoredAlignmentFailed, path: .alignmentFailed, confidence: 0,
                          safety: .unsafe(reason: "dimensions"), includePage: renderMergedImage)
        }
        if next == viewport {
            return update(outcome: .ignoredNoMovement, path: .noMovement, confidence: 1,
                          boundary: true, includePage: renderMergedImage)
        }
        let header = matchingRun(previous: viewport, current: next, fromTop: true)
        let footer = matchingRun(previous: viewport, current: next, fromTop: false)
        let content = viewportHeight - header - footer
        guard content > 1 else {
            failures += 1
            return update(outcome: .ignoredAlignmentFailed, path: .alignmentFailed, confidence: 0,
                          includePage: renderMergedImage)
        }
        let delta: Int
        let score: Int
        if let expectedSignedDeltaPixels {
            let proposed = abs(expectedSignedDeltaPixels)
            let measured = overlapDistance(previous: viewport, current: next, delta: proposed, header: header, footer: footer)
            if proposed > 0, proposed < content, measured <= 2 {
                delta = proposed
                score = measured
            } else if allowsSettledPartialStep, let found = searchDelta(previous: viewport, current: next, header: header, footer: footer) {
                delta = found.delta
                score = found.score
            } else {
                failures += 1
                return update(outcome: .ignoredAlignmentFailed, path: .alignmentFailed, confidence: 0,
                              score: Double(measured), includePage: renderMergedImage)
            }
        } else if let found = searchDelta(previous: viewport, current: next, header: header, footer: footer) {
            delta = found.delta
            score = found.score
        } else {
            failures += 1
            return update(outcome: .ignoredAlignmentFailed, path: .alignmentFailed, confidence: 0,
                          includePage: renderMergedImage)
        }
        let room = maxOutputHeight - outputHeight
        if room <= 0 {
            return update(outcome: .reachedHeightLimit, path: .heightLimit, confidence: 1,
                          delta: delta, includePage: renderMergedImage)
        }
        let take = min(delta, room)
        if !trimmedBands && (header > 0 || footer > 0) {
            cropStoredBands(header: header, footer: footer)
            trimmedBands = true
        }
        headerRows = header
        footerRows = footer
        let start = header + (content - delta)
        let fresh = Data(next[(start * width * 4)..<((start + take) * width * 4)])
        store(fresh, rows: take)
        viewport = next
        direction = .appendFromBottom
        cachedPage = nil
        acceptedFrameCount += 1
        if take < delta {
            return update(outcome: .reachedHeightLimit, path: .heightLimit, confidence: 1,
                          score: Double(score), delta: take, includePage: renderMergedImage)
        }
        return update(outcome: .appended(deltaY: delta), path: .fastGuided, confidence: score == 0 ? 1 : 0.5,
                      score: Double(score), delta: delta, includePage: renderMergedImage)
    }

    func mergedImage() -> CGImage? {
        if let cachedPage { return cachedPage }
        guard width > 0, outputHeight > 0 else { return nil }
        let reader = StripReader(strips: strips, bytesPerRow: width * 4)
        let retained = Unmanaged.passRetained(reader)
        var callbacks = CGDataProviderDirectCallbacks(
            version: 0, getBytePointer: nil, releaseBytePointer: nil,
            getBytesAtPosition: { info, buffer, position, count in
                guard let info else { return 0 }
                return Unmanaged<StripReader>.fromOpaque(info).takeUnretainedValue()
                    .read(into: buffer, position: Int(position), count: count)
            },
            releaseInfo: { info in
                if let info { Unmanaged<StripReader>.fromOpaque(info).release() }
            })
        guard let provider = CGDataProvider(directInfo: retained.toOpaque(), size: off_t(reader.byteCount), callbacks: &callbacks) else {
            retained.release()
            return nil
        }
        cachedPage = CGImage(width: width, height: outputHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                             bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                             provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        return cachedPage
    }

    func previewImage(maxPixelWidth: Int, maxPixelHeight: Int) -> CGImage? {
        guard width > 0, outputHeight > 0 else { return nil }
        let scale = min(1, Double(max(1, maxPixelWidth)) / Double(width), Double(max(1, maxPixelHeight)) / Double(outputHeight))
        let targetWidth = max(1, Int((Double(width) * scale).rounded()))
        let targetHeight = max(1, Int((Double(outputHeight) * scale).rounded()))
        guard let page = joinedRows() else { return nil }
        var preview = [UInt8](repeating: 0, count: targetWidth * targetHeight * 4)
        for y in 0..<targetHeight {
            let sourceY = min(outputHeight - 1, y * outputHeight / targetHeight)
            for x in 0..<targetWidth {
                let sourceX = min(width - 1, x * width / targetWidth)
                let from = (sourceY * width + sourceX) * 4
                let to = (y * targetWidth + x) * 4
                preview[to] = page[from]
                preview[to + 1] = page[from + 1]
                preview[to + 2] = page[from + 2]
                preview[to + 3] = page[from + 3]
            }
        }
        return image(width: targetWidth, rows: Data(preview))
    }

    func forEachStrip(_ body: (CGImage) throws -> Void) throws {
        for strip in strips {
            guard let rows = strip.rows(), let image = image(width: width, rows: rows) else {
                throw StitchingFailure.imageUnavailable
            }
            try body(image)
        }
    }

    private func store(_ rows: Data, rows rowCount: Int) {
        var pending = Data()
        var pendingRows = 0
        if let last = strips.last, last.rowCount < 256, let existing = last.rows() {
            pending = existing
            pendingRows = last.rowCount
            strips.removeLast()
        }
        var offset = 0
        let bytesPerRow = width * 4
        var remaining = rowCount
        while remaining > 0 {
            let take = min(256 - pendingRows, remaining)
            let byteCount = take * bytesPerRow
            pending.append(rows[rows.startIndex + offset..<rows.startIndex + offset + byteCount])
            pendingRows += take
            offset += byteCount
            remaining -= take
            if pendingRows == 256 {
                strips.append(Strip(rows: pending, rowCount: 256))
                pending = Data()
                pendingRows = 0
            }
        }
        if pendingRows > 0 { strips.append(Strip(rows: pending, rowCount: pendingRows)) }
    }

    private func store(_ pixels: [UInt8], rows: Int) {
        store(Data(pixels), rows: rows)
    }

    private func cropStoredBands(header: Int, footer: Int) {
        guard let all = joinedRows() else { return }
        let rows = all.count / (width * 4)
        let end = rows - footer
        guard header < end else { return }
        let kept = all.subdata(in: header * width * 4..<end * width * 4)
        strips = []
        cachedPage = nil
        store(kept, rows: end - header)
    }

    private func joinedRows() -> Data? {
        var all = Data()
        for strip in strips {
            guard let rows = strip.rows() else { return nil }
            all.append(rows)
        }
        return all
    }

    private func matchingRun(previous: [UInt8], current: [UInt8], fromTop: Bool) -> Int {
        let limit = viewportHeight / 3
        var count = 0
        while count < limit {
            let row = fromTop ? count : viewportHeight - 1 - count
            if rowDistance(previous, current, row, row) > 0 { break }
            count += 1
        }
        return count
    }

    private func overlapDistance(previous: [UInt8], current: [UInt8], delta: Int, header: Int, footer: Int) -> Int {
        let content = viewportHeight - header - footer
        let overlap = content - delta
        guard overlap > 0 else { return Int.max }
        var total = 0
        var samples = 0
        var row = 0
        let stride = max(1, overlap / 24)
        while row < overlap {
            total += rowDistance(previous, current, header + delta + row, header + row)
            samples += 1
            row += stride
        }
        return total / max(samples, 1)
    }

    private func searchDelta(previous: [UInt8], current: [UInt8], header: Int, footer: Int) -> (delta: Int, score: Int)? {
        let content = viewportHeight - header - footer
        var bestDelta = 0
        var best = Int.max
        var delta = 1
        while delta < content {
            let score = overlapDistance(previous: previous, current: current, delta: delta, header: header, footer: footer)
            if score < best {
                best = score
                bestDelta = delta
                if score == 0 { break }
            }
            delta += 1
        }
        guard best <= 2, bestDelta > 0 else { return nil }
        return (bestDelta, best)
    }

    private func rowDistance(_ left: [UInt8], _ right: [UInt8], _ leftRow: Int, _ rightRow: Int) -> Int {
        let step = max(1, width / 24)
        var total = 0
        var samples = 0
        var x = 0
        while x < width {
            let a = (leftRow * width + x) * 4
            let b = (rightRow * width + x) * 4
            total += abs(Int(left[a]) - Int(right[b]))
            total += abs(Int(left[a + 1]) - Int(right[b + 1]))
            total += abs(Int(left[a + 2]) - Int(right[b + 2]))
            samples += 3
            x += step
        }
        return total / max(samples, 1)
    }

    private func update(
        outcome: ScrollingCaptureStitchOutcome,
        path: ScrollingCaptureAlignmentPath,
        confidence: Double,
        score: Double? = nil,
        delta: Int? = nil,
        boundary: Bool = false,
        safety: ScrollingCaptureStitchSafety = .confirmed,
        includePage: Bool
    ) -> ScrollingCaptureStitchUpdate {
        ScrollingCaptureStitchUpdate(
            outcome: outcome,
            mergedImage: includePage ? mergedImage() : nil,
            acceptedFrameCount: acceptedFrameCount,
            outputHeight: outputHeight,
            matchFailureCount: failures,
            mergeDirection: direction,
            likelyReachedBoundary: boundary,
            safety: safety,
            alignmentDebug: ScrollingCaptureAlignmentDebugInfo(
                path: path, usedVisionEstimate: false, confidence: confidence,
                pixelScore: score, totalScore: score, appendDeltaY: delta, visionAgreementCount: 0))
    }

    private func copiedPixels(_ image: CGImage) -> [UInt8]? {
        let count = image.width * image.height * 4
        guard image.bitsPerPixel == 32, image.bytesPerRow == image.width * 4,
              let data = image.dataProvider?.data as Data?, data.count == count else { return nil }
        return [UInt8](data)
    }

    private func image(width: Int, rows: Data) -> CGImage? {
        let height = rows.count / (width * 4)
        guard height > 0, let provider = CGDataProvider(data: rows as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
