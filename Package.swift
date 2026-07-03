// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lidopen",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "LidopenCore",
            targets: ["LidopenCore"]
        ),
        .executable(
            name: "Lidopen",
            targets: ["Lidopen"]
        ),
    ],
    targets: [
        .target(
            name: "LidopenCore",
            path: "Sources/LidopenCore"
        ),
        .executableTarget(
            name: "Lidopen",
            dependencies: ["LidopenCore"],
            path: "Sources/Lidopen"
        ),
        .testTarget(
            name: "LidopenCoreTests",
            dependencies: ["LidopenCore"],
            path: "Tests/LidopenCoreTests"
        ),
    ]
)
