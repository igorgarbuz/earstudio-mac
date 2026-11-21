// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EarStudioKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        // App hosts link one product so Xcode can share it with hosted tests.
        // Individual products remain available for clients needing only one layer.
        .library(name: "EarStudioKit", targets: ["EarStudioCore", "EarStudioSession", "EarStudioUI", "EarStudioAssets"]),
        .library(name: "EarStudioCore", targets: ["EarStudioCore"]),
        .library(name: "EarStudioSession", targets: ["EarStudioSession"]),
        .library(name: "EarStudioUI", targets: ["EarStudioUI"]),
        .library(name: "EarStudioAssets", targets: ["EarStudioAssets"])
    ],
    targets: [
        .target(name: "EarStudioCore"),
        .target(name: "EarStudioSession", dependencies: ["EarStudioCore"]),
        .target(name: "EarStudioAssets", resources: [.process("Resources")]),
        .target(name: "EarStudioUI", dependencies: ["EarStudioCore", "EarStudioSession", "EarStudioAssets"]),
        .target(name: "EarStudioTestSupport", dependencies: ["EarStudioCore"], path: "Tests/Support"),
        .testTarget(name: "EarStudioCoreTests", dependencies: ["EarStudioCore", "EarStudioTestSupport"]),
        .testTarget(name: "EarStudioSessionTests", dependencies: ["EarStudioSession", "EarStudioCore", "EarStudioUI", "EarStudioTestSupport"])
    ]
)
