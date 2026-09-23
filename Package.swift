// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Frisket",
    platforms: [.macOS(.v26)],
    products: [.library(name: "FrisketCore", type: .static, targets: ["FrisketCore"])],
    targets: [
        .target(name: "FrisketCore"),
        .testTarget(name: "FrisketCoreTests", dependencies: ["FrisketCore"]),
        // Compile the same app adapters without an app host for seam-1 tests.
        .target(name: "FrisketAdapters", dependencies: ["FrisketCore"], path: "Frisket/Adapters"),
        .testTarget(name: "FrisketAdapterTests", dependencies: ["FrisketCore", "FrisketAdapters"])
    ]
)
