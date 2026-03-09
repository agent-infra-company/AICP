// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AICP",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AICP",
            targets: ["AICP"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/rive-app/rive-ios", from: "6.13.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "AICP",
            dependencies: [
                .product(name: "RiveRuntime", package: "rive-ios"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "AICPTests",
            dependencies: ["AICP"]
        )
    ]
)
