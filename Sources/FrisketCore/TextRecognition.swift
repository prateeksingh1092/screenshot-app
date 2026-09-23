import Foundation

/// Runs only on the bytes of one revision. Implementations must not persist the text.
public protocol TextRecognizer: Sendable {
    func recognize(_ image: CaptureImage) async -> String
}

/// Write-only text clipboard. The core never reads it back.
public protocol TextClipboard: Sendable {
    func writeText(_ text: String) async -> Result<ClipboardReceipt, ClipboardFailure>
}

/// Delivery of recognized text. The string itself is not part of the outcome.
public struct RecognizedTextOutcome: Equatable, Sendable {
    public let revision: CaptureRevision
    public let characterCount: Int
    public let delivery: DeliveryOutcome
    public init(revision: CaptureRevision, characterCount: Int, delivery: DeliveryOutcome) {
        self.revision = revision
        self.characterCount = characterCount
        self.delivery = delivery
    }
}
