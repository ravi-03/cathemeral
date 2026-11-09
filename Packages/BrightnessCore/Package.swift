// swift-tools-version:6.0
// The rules of Cathemeral: display ownership, levels and gamma maths. No AppKit.
import PackageDescription

let package = Package(
    name: "BrightnessCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BrightnessCore", targets: ["BrightnessCore"])
    ],
    targets: [
        .target(name: "BrightnessCore"),
        .testTarget(name: "BrightnessCoreTests", dependencies: ["BrightnessCore"]),
    ]
)
