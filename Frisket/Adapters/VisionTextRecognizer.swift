import Foundation
import FrisketCore
import ImageIO
import Vision

/// On-device Vision OCR. The recognized string is returned to the command layer only.
struct VisionTextRecognizer: TextRecognizer {
    func recognize(_ image: CaptureImage) async -> String {
        let source = CGImageSourceCreateWithData(image.pngData as CFData, nil)
        guard let cgImage = source.flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
    }
}