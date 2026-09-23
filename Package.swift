// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Frisket",
    platforms: [.macOS(.v26)],
    products: [.library(name: "FrisketCore", type: .static, targets: ["FrisketCore"])],
    targets: [
        .target(name: "FrisketCore"),
        .testTarget(name: "FrisketCoreTests", dependencies: ["FrisketCore"])
    ]
)
