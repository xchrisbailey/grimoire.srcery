// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "GrimoireEditor",
    platforms: [.macOS(.v27), .iOS(.v27)],
    products: [
        .library(name: "GrimoireEditor", targets: ["GrimoireEditor"])
    ],
    dependencies: [
        .package(path: "../GrimoireCore")
    ],
    targets: [
        .target(
            name: "GrimoireEditor",
            dependencies: ["GrimoireCore"]
        ),
        .testTarget(
            name: "GrimoireEditorTests",
            dependencies: ["GrimoireEditor"]
        ),
    ]
)
