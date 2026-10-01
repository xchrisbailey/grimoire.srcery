// swift-tools-version: 6.4
import PackageDescription

/// Tree-sitter grammars for code blocks (#13). Versions are pinned: several grammars'
/// newer manifests only add their external scanner when a relative path exists at
/// manifest time, which SwiftPM doesn't guarantee, and the build then fails to link.
enum Pin {
    case exact(Version)
    case revision(String)
}

struct Grammar {
    var product: String
    var package: String
    var url: String
    var pin: Pin

    init(_ product: String, _ package: String, _ url: String, _ pin: Pin) {
        (self.product, self.package, self.url, self.pin) = (product, package, url, pin)
    }
}

let grammars: [Grammar] = [
    Grammar(
        "TreeSitterSwift", "tree-sitter-swift", "alex-pinkus/tree-sitter-swift", .exact("0.7.3-with-generated-files")),
    Grammar("TreeSitterJavaScript", "tree-sitter-javascript", "tree-sitter/tree-sitter-javascript", .exact("0.23.1")),
    Grammar("TreeSitterTypeScript", "tree-sitter-typescript", "tree-sitter/tree-sitter-typescript", .exact("0.23.2")),
    Grammar("TreeSitterPython", "tree-sitter-python", "tree-sitter/tree-sitter-python", .exact("0.23.6")),
    Grammar("TreeSitterGo", "tree-sitter-go", "tree-sitter/tree-sitter-go", .exact("0.23.4")),
    Grammar("TreeSitterRust", "tree-sitter-rust", "tree-sitter/tree-sitter-rust", .exact("0.24.2")),
    Grammar("TreeSitterJSON", "tree-sitter-json", "tree-sitter/tree-sitter-json", .exact("0.24.8")),
    Grammar("TreeSitterBash", "tree-sitter-bash", "tree-sitter/tree-sitter-bash", .exact("0.25.1")),
    Grammar("TreeSitterHTML", "tree-sitter-html", "tree-sitter/tree-sitter-html", .exact("0.23.2")),
    Grammar("TreeSitterCSS", "tree-sitter-css", "tree-sitter/tree-sitter-css", .exact("0.23.2")),
    Grammar("TreeSitterC", "tree-sitter-c", "tree-sitter/tree-sitter-c", .exact("0.24.2")),
    Grammar("TreeSitterCPP", "tree-sitter-cpp", "tree-sitter/tree-sitter-cpp", .exact("0.23.4")),
    Grammar("TreeSitterRuby", "tree-sitter-ruby", "tree-sitter/tree-sitter-ruby", .exact("0.23.1")),
    Grammar("TreeSitterYAML", "tree-sitter-yaml", "tree-sitter-grammars/tree-sitter-yaml", .exact("0.7.0")),
    Grammar("TreeSitterTOML", "tree-sitter-toml", "tree-sitter-grammars/tree-sitter-toml", .exact("0.7.0")),
    Grammar("TreeSitterMarkdown", "tree-sitter-markdown", "tree-sitter-grammars/tree-sitter-markdown", .exact("0.5.3")),
    // The SQL grammar keeps its generated parser on the gh-pages branch.
    Grammar(
        "TreeSitterSql", "tree-sitter-sql", "DerekStride/tree-sitter-sql",
        .revision("39fdb006403747241244326e8af3b3e96b85381c")
    ),
]

let package = Package(
    name: "GrimoireEditor",
    platforms: [.macOS(.v27), .iOS(.v27)],
    products: [
        .library(name: "GrimoireEditor", targets: ["GrimoireEditor"])
    ],
    dependencies: [
        .package(path: "../GrimoireCore"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.25.0"),
    ]
        + grammars.map { grammar in
            let url = "https://github.com/\(grammar.url)"
            switch grammar.pin {
            case .exact(let version): return .package(url: url, exact: version)
            case .revision(let revision): return .package(url: url, revision: revision)
            }
        },
    targets: [
        .target(
            name: "GrimoireEditor",
            dependencies: [
                "GrimoireCore",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
            ]
                + grammars.map { .product(name: $0.product, package: $0.package) }
        ),
        .testTarget(
            name: "GrimoireEditorTests",
            dependencies: ["GrimoireEditor"]
        ),
    ]
)
