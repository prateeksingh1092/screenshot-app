// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Frisket",
    platforms: [.macOS(.v26)],
    products: [.library(name: "FrisketCore", type: .static, targets: ["FrisketCore"])],
    dependencies: [.package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")],
    targets: [
        .target(name: "FrisketCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "FrisketCoreTests", dependencies: ["FrisketCore"]),
        // Compile the same app adapters without an app host for seam-1 tests.
        .target(name: "FrisketAdapters", dependencies: ["FrisketCore"], path: "Frisket/Adapters"),
        .testTarget(name: "FrisketAdapterTests", dependencies: ["FrisketCore", "FrisketAdapters"])
    ]
)
