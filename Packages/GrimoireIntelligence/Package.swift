// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "GrimoireIntelligence",
    platforms: [.macOS(.v27), .iOS(.v27)],
    products: [
        .library(name: "GrimoireIntelligence", targets: ["GrimoireIntelligence"])
    ],
    dependencies: [
        .package(path: "../GrimoireCore")
    ],
    targets: [
        .target(
            name: "GrimoireIntelligence",
            dependencies: ["GrimoireCore"]
        ),
        .testTarget(
            name: "GrimoireIntelligenceTests",
            dependencies: ["GrimoireIntelligence"]
        ),
    ]
)
