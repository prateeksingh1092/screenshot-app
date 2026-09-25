// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Frisket",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FrisketCore", type: .static, targets: ["FrisketCore"]),
        // The app links the adapters it runs; it compiles none of them itself (ticket 77).
        .library(name: "FrisketAdapters", type: .static, targets: ["FrisketAdapters"])
    ],
    dependencies: [.package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")],
    targets: [
        .target(name: "FrisketCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(name: "HistoryCrashHelper", dependencies: ["FrisketCore"], path: "Tests/Helpers/HistoryCrashHelper"),
        .testTarget(name: "FrisketCoreTests", dependencies: ["FrisketCore", "HistoryCrashHelper"]),
        // The AppKit, ScreenCaptureKit and Vision adapters: linked by the app, tested without an app host.
        .target(name: "FrisketAdapters", dependencies: ["FrisketCore"], path: "Frisket/Adapters"),
        .testTarget(name: "FrisketAdapterTests", dependencies: ["FrisketCore", "FrisketAdapters"])
    ]
)
