// Test-only executable. Never linked into the Xcode app target.
import Foundation
import Darwin
import FrisketCore

private struct Pixels: CapturePixelSource {
    func capture(maximumBytes: Int) async -> Result<CaptureImage, CaptureSourceFailure> {
        .success(CaptureImage(pngData: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4z8AARAAI/gH/xp559wAAAABJRU5ErkJggg==")!))
    }
}

private struct Clipboard: ImageClipboard {
    func write(_ image: ClipboardImage) async -> Result<ClipboardReceipt, ClipboardFailure> { .failure(.unavailable) }
}

@main enum HistoryCrashHelper {
    static func main() async {
        guard [4, 5].contains(CommandLine.arguments.count),
              let point = HistoryCommitPoint(rawValue: CommandLine.arguments[2]),
              let uuid = UUID(uuidString: CommandLine.arguments[3]) else { Darwin._exit(64) }
        let store = HistoryStore(root: URL(fileURLWithPath: CommandLine.arguments[1]),
            clock: { Date(timeIntervalSince1970: 1234) }, commitPoint: { reached in
                if reached == point {
                    if CommandLine.arguments.count == 5 {
                        FileHandle.standardOutput.write(Data([1]))
                        _ = FileHandle.standardInput.readData(ofLength: 1)
                    }
                    guard kill(getpid(), SIGKILL) == 0 else { Darwin._exit(65) }
                    while true { pause() }
                }
            })
        let commands = CaptureCommandLayer(source: Pixels(), clipboard: Clipboard(), pendingByteLimit: 1024, history: store)
        let id = CaptureID(uuid)
        _ = await commands.execute(.capture(id, maximumBytes: 1024))
        _ = await commands.execute(.dismiss(CaptureRevision(captureID: id, number: 1)))
        Darwin._exit(66) // No selected point reached: the parent test must fail.
    }
}
