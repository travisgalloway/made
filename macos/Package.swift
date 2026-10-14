// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MadeNative",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "MadeCore",
            targets: ["MadeCore"]
        ),
        .executable(
            name: "MadeApp",
            targets: ["MadeApp"]
        ),
        .executable(
            name: "MadeKernelService",
            targets: ["MadeKernelService"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/Euclid.git", from: "0.9.6")
    ],
    targets: [
        .target(
            name: "MadeCore",
            dependencies: [
                .product(name: "Euclid", package: "Euclid")
            ],
            path: "Sources/MadeCore",
            resources: [
                .process("Viewport/Shaders.metal"),
                .copy("Licenses/Resources")
            ]
        ),
        .executableTarget(
            name: "MadeApp",
            dependencies: ["MadeCore"],
            path: "Sources/MadeApp"
        ),
        .executableTarget(
            name: "MadeKernelService",
            dependencies: ["MadeCore"],
            path: "Sources/MadeKernelService"
        ),
        .testTarget(
            name: "MadeCoreTests",
            dependencies: ["MadeCore"],
            path: "Tests/MadeCoreTests"
        )
    ]
)
