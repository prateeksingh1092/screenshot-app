import Foundation

/// Downsampled canvas for the editor. Done still renders the full-resolution strips.
public enum EditorProxy {
    public static let maxEdge = 2048

    public static func displaySize(width: Int, height: Int, maxEdge: Int = maxEdge) -> (width: Int, height: Int) {
        let edge = max(1, maxEdge)
        guard width > 0, height > 0 else { return (1, 1) }
        if width <= edge, height <= edge { return (width, height) }
        let scale = Double(edge) / Double(max(width, height))
        return (max(1, Int((Double(width) * scale).rounded())),
                max(1, Int((Double(height) * scale).rounded())))
    }

    public static func displayScale(fullWidth: Int, proxyWidth: Int, scale: Double) -> Double {
        guard fullWidth > 0 else { return scale }
        return scale * Double(proxyWidth) / Double(fullWidth)
    }
}
