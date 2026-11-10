// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DisplayStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DisplayStudio", targets: ["DisplayStudio"])
    ],
    targets: [
        .executableTarget(
            name: "DisplayStudio",
            path: "Sources/DisplayStudio",
            exclude: [
                "Engine/Shaders.metal"
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreImage"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Speech"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .testTarget(
            name: "DisplayStudioTests",
            dependencies: ["DisplayStudio"],
            path: "Tests/DisplayStudioTests"
        )
    ]
)
