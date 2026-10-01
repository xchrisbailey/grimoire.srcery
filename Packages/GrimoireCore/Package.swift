// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "GrimoireCore",
    platforms: [.macOS(.v27), .iOS(.v27)],
    products: [
        .library(name: "GrimoireCore", targets: ["GrimoireCore"])
    ],
    targets: [
        .target(
            name: "GrimoireCore"
        ),
        .testTarget(
            name: "GrimoireCoreTests",
            dependencies: ["GrimoireCore"]
        ),
    ]
)
