import Testing

@testable import GrimoireCore

@Suite struct BrandPaletteTests {
    @Test func mochaMatchesTheBrandBook() {
        let mocha = BrandPalette.mocha
        #expect(mocha.isDark)
        #expect(mocha.page.description == "#1e1e2e")
        #expect(mocha.sidebar.description == "#181825")
        #expect(mocha.ink.description == "#cdd6f4")
        #expect(mocha.magic.description == "#cba6f7")
        #expect(mocha.caret.description == "#fab387")
        #expect(mocha.error.description == "#f38ba8")
    }

    @Test func latteMatchesTheBrandBook() {
        let latte = BrandPalette.latte
        #expect(!latte.isDark)
        #expect(latte.page.description == "#eff1f5")
        #expect(latte.ink.description == "#4c4f69")
        #expect(latte.magic.description == "#8839ef")
        #expect(latte.caret.description == "#fe640b")
        #expect(latte.quote.description == "#179299")
    }

    @Test func defaultFollowsAppearance() {
        #expect(BrandPalette.default(dark: true) == .mocha)
        #expect(BrandPalette.default(dark: false) == .latte)
        #expect(BrandPalette.builtIn.map(\.name) == ["Catppuccin Mocha", "Catppuccin Latte"])
    }
}
