// swift-tools-version: 6.3
import PackageDescription

// Isolated evaluation only; Frisket must never depend on this package.
let package = Package(
    name: "StitcherTrial",
    platforms: [.macOS(.v26)],
    products: [.library(name: "StitcherTrial", targets: ["StitcherTrial"])],
    targets: [
        .target(name: "StitcherTrial"),
        .testTarget(name: "StitcherTrialTests", dependencies: ["StitcherTrial"])
    ]
)
