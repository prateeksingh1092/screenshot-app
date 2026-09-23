import CoreGraphics
import Foundation
import ImageIO
import FrisketCore

/// Test-only disk adapter. The stitcher itself receives only in-memory frames.
struct RecordedScrollSequence {
  private struct Manifest: Decodable {
    struct Provenance: Decodable {
      let kind: String
      let source: String
      let authorization: String
      let osBuild: String
    }
    struct Frame: Decodable {
      let file: String
      let expectedVerticalStep: Int?
      let isSettled: Bool?
    }
    struct Band: Decodable {
      let referenceRow: Int
      let height: Int
    }
    let version: Int
    let provenance: Provenance
    let frames: [Frame]
    let reference: String
    let expectedWidth: Int
    let expectedHeight: Int
    let heightTolerance: Int
    let uniqueBands: [Band]
  }

  enum FixtureFailure: Error { case invalidManifest, invalidImage, invalidBand }
  let frames: [ScrollingCaptureFrame]
  let reference: CGImage
  private let manifest: Manifest
  var isRecorded: Bool { manifest.provenance.kind == "recorded" }

  static func load(at folder: URL) throws -> Self {
    let manifest = try JSONDecoder().decode(Manifest.self,
      from: Data(contentsOf: folder.appendingPathComponent("sequence.json")))
    guard manifest.version == 1, !manifest.frames.isEmpty, !manifest.uniqueBands.isEmpty,
      manifest.expectedWidth > 0, manifest.expectedHeight > 0, manifest.heightTolerance >= 0,
      ["synthetic", "recorded"].contains(manifest.provenance.kind),
      !manifest.provenance.source.isEmpty, !manifest.provenance.authorization.isEmpty,
      !manifest.provenance.osBuild.isEmpty else { throw FixtureFailure.invalidManifest }
    func image(_ name: String) throws -> CGImage {
      guard !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent,
        name.hasSuffix(".png") else { throw FixtureFailure.invalidManifest }
      let bytes = try Data(contentsOf: folder.appendingPathComponent(name))
      guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw FixtureFailure.invalidImage }
      return image
    }
    return try Self(frames: manifest.frames.map {
      ScrollingCaptureFrame(image: try image($0.file), expectedVerticalStep: $0.expectedVerticalStep,
        isSettled: $0.isSettled ?? false)
    }, reference: image(manifest.reference), manifest: manifest)
  }

  func rgba(_ image: CGImage) throws -> Data {
    var bytes = Data(count: image.width * image.height * 4)
    try bytes.withUnsafeMutableBytes { buffer in
      guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { throw FixtureFailure.invalidImage }
      context.interpolationQuality = .none
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
  }

  /// A human-authored reference and deliberately unique bands form the oracle.
  /// Every listed band must occur exactly once in both reference and result,
  /// in reference order. This detects duplicated seams even at an allowed height.
  func validationIssues(for image: CGImage) throws -> [String] {
    guard reference.width == manifest.expectedWidth,
      reference.height == manifest.expectedHeight else { throw FixtureFailure.invalidManifest }
    var issues: [String] = []
    if abs(image.height - manifest.expectedHeight) > manifest.heightTolerance {
      issues.append("height outside tolerance")
    }
    guard image.width == manifest.expectedWidth else { return issues + ["unexpected width"] }
    let expected = try rgba(reference), actual = try rgba(image)
    let rowBytes = image.width * 4
    var previousRow = -1
    var previousReferenceRow = -1
    for band in manifest.uniqueBands {
      guard band.referenceRow > previousReferenceRow, band.height > 0,
        band.referenceRow >= 0, band.referenceRow <= reference.height - band.height else {
        throw FixtureFailure.invalidBand
      }
      previousReferenceRow = band.referenceRow
      let start = band.referenceRow * rowBytes
      let needle = expected.subdata(in: start..<(start + band.height * rowBytes))
      func occurrences(in data: Data, height: Int) -> [Int] {
        guard height >= band.height else { return [] }
        return data.withUnsafeBytes { haystack in
          needle.withUnsafeBytes { target in
            (0...(height - band.height)).filter { row in
              memcmp(haystack.baseAddress!.advanced(by: row * rowBytes), target.baseAddress!, needle.count) == 0
            }
          }
        }
      }
      guard occurrences(in: expected, height: reference.height).count == 1 else { throw FixtureFailure.invalidBand }
      let found = occurrences(in: actual, height: image.height)
      if found.count != 1 {
        issues.append("band occurrences at reference row \(band.referenceRow): \(found.count), expected 1")
      } else if let row = found.first {
        if row <= previousRow { issues.append("bands out of order") }
        previousRow = row
      }
    }
    return issues
  }
}
