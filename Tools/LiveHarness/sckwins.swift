// sckwins [MAXSIDE]: ScreenCaptureKit's view of on-screen windows no larger than MAXSIDE points
// (default 64), with owner bundle ID and CG stacking order. D2 evidence: the cursor is listed
// as a window whose owner has an empty bundle ID.
import ScreenCaptureKit

@main struct SCKWindows {
    static func main() async throws {
        let maxSide = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 64 : 64
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let cg = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let order = cg.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        for w in content.windows where w.frame.width <= maxSide && w.frame.height <= maxSide {
            let owner = w.owningApplication
            print("id=\(w.windowID) frame=\(w.frame) layer=\(w.windowLayer) owner=\(owner?.applicationName ?? "nil") bundle=\(owner.map { $0.bundleIdentifier.debugDescription } ?? "nil") title=\((w.title ?? "").debugDescription) cgOrder=\(order.firstIndex(of: w.windowID).map(String.init) ?? "-")")
        }
    }
}
