// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "GrimoireCore",
    platforms: [.macOS(.v27), .iOS(.v27)],
    products: [
        .library(name: "GrimoireCore", targets: ["GrimoireCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "GrimoireCore",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")]
        ),
        .testTarget(
            name: "GrimoireCoreTests",
            dependencies: ["GrimoireCore"],
            resources: [.copy("Corpus")]
        ),
    ]
)
