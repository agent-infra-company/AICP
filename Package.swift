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
    targets: [
        .executableTarget(
            name: "ClawdbotNotchCompanion"
        ),
        .testTarget(
            name: "ClawdbotNotchCompanionTests",
            dependencies: ["ClawdbotNotchCompanion"]
        )
    ]
)
