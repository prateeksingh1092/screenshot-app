import Foundation

/// Writes a drag's promised file from memory to the destination the receiver provides.
/// Nothing is staged under the History root; the app may not write files itself.
public actor DragPromiseWriter {
    public init() {}

    public func writePromiseCopy(_ pngData: Data, to destination: URL) async throws {
        try pngData.write(to: destination, options: .atomic)
    }
}
