// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ClawdbotNotchCompanion",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ClawdbotNotchCompanion",
            targets: ["ClawdbotNotchCompanion"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/rive-app/rive-ios", from: "6.13.0")
    ],
    targets: [
        .executableTarget(
            name: "ClawdbotNotchCompanion",
            dependencies: [
                .product(name: "RiveRuntime", package: "rive-ios")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ClawdbotNotchCompanionTests",
            dependencies: ["ClawdbotNotchCompanion"]
        )
    ]
)
