// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EarStudioCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "EarStudioCore", targets: ["EarStudioCore"])],
    targets: [
        .target(name: "EarStudioCore", path: "Sources/Core"),
        .testTarget(name: "EarStudioCoreTests", dependencies: ["EarStudioCore"], path: "Tests")
    ]
)
