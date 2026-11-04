// swift-tools-version:5.10
import PackageDescription

// Layout:
//   EQCore  – portable, platform-independent engine (DSP, presets, headphone
//             profiles, backend protocol). No Apple frameworks: builds on
//             macOS, iOS, Linux, Windows and Android Swift toolchains.
//   HeadEQ  – macOS app: SwiftUI UI + Core Audio process-tap backend.
let package = Package(
    name: "HeadEQ",
    platforms: [.macOS("14.2"), .iOS(.v17)],
    products: [
        .library(name: "EQCore", targets: ["EQCore"]),
        .executable(name: "HeadEQ", targets: ["HeadEQ"]),
        .executable(name: "make-icon", targets: ["make-icon"]),
    ],
    targets: [
        .target(name: "EQCore", path: "Sources/EQCore"),
        // App icon / menu-bar glyph artwork, shared by the app and the icon tool.
        .target(name: "HeadEQArt", path: "Sources/HeadEQArt"),
        .executableTarget(name: "make-icon", dependencies: ["HeadEQArt"], path: "Sources/make-icon"),
        .executableTarget(
            name: "HeadEQ",
            dependencies: ["EQCore", "HeadEQArt"],
            path: "Sources/HeadEQ",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
            ]
        ),
        .testTarget(name: "EQCoreTests", dependencies: ["EQCore"], path: "Tests/EQCoreTests"),
    ]
)
