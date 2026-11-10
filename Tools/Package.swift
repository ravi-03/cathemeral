// swift-tools-version:6.0
// End-to-end tools for checking dimming on the real screen. Not shipped in the app.
// See Tools/README.md.
import PackageDescription

let package = Package(
    name: "Tools",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Packages/BrightnessCore"),
        .package(path: "../Packages/BrightnessPlatform"),
    ],
    targets: [
        .executableTarget(
            name: "harness",
            dependencies: [
                .product(name: "BrightnessCore", package: "BrightnessCore"),
                .product(name: "BrightnessPlatform", package: "BrightnessPlatform"),
            ]
        ),
        .executableTarget(name: "peek"),
    ]
)
