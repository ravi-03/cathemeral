// swift-tools-version:6.0
// Thin wrappers around the macOS APIs Cathemeral needs. Covered by the spike and the manual
// checklist, not by unit tests (see the PRD's Testing Decisions).
import PackageDescription

let package = Package(
    name: "BrightnessPlatform",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BrightnessPlatform", targets: ["BrightnessPlatform"])
    ],
    dependencies: [
        .package(path: "../BrightnessCore")
    ],
    targets: [
        .target(name: "BrightnessPlatform", dependencies: ["BrightnessCore"])
    ]
)
