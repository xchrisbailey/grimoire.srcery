import Testing

@testable import GrimoireCore

@Test func documentExtensionsCoverMarkdownAndMDX() {
    #expect(GrimoireCore.documentExtensions == ["md", "mdx"])
}
