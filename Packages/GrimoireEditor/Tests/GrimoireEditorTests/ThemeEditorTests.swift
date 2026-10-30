#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

@MainActor @Suite(.serialized) struct ThemeEditorTests {
    static let sample = """
        ---
        title: Potions
        ---

        # Potion ledger

        - Ember **draught**

        """

    /// A dark theme with loud, easy-to-spot colors.
    static let neon: Theme = {
        var palette = BrandPalette.mocha
        palette.name = "Neon"
        palette.page = PaletteColor(hex: 0x000000)
        palette.magic = PaletteColor(hex: 0xff00ff)
        palette.caret = PaletteColor(hex: 0x00ff00)
        var theme = Theme(
            id: "neon", name: "Neon", isDark: true, origin: .imported(fileName: "neon.json"), palette: palette)
        theme.raw[.heading1] = TokenStyle(color: PaletteColor(hex: 0x123456), bold: false)
        theme.preview[.heading1] = TokenStyle(color: PaletteColor(hex: 0x654321))
        return theme
    }()

    var heading: Int { (Self.sample as NSString).range(of: "Potion ledger").location }

    @Test(arguments: [false, true]) func appearanceKeepsThemeAndRenderingTogether(dark: Bool) throws {
        let controller = makeEditor(Self.sample, dark: dark, mode: .raw)
        let window = try #require(controller.textView.window)
        #expect(controller.textView.isDarkAppearance == dark)
        controller.theme = EditorTheme(light: .latte, dark: Self.neon)
        #expect(controller.styler.theme.isDark == dark)
        #expect(controller.styler.theme.current.id == (dark ? "neon" : Theme.latte.id))
        #expect(controller.color(at: heading) == (dark ? PaletteColor(hex: 0x123456) : BrandPalette.latte.magic))
        let font = try #require(controller.font(at: heading))
        #expect((NSFontManager.shared.weight(of: font) < 9) == dark)

        window.appearance = NSAppearance(named: dark ? .aqua : .darkAqua)
        #expect(controller.styler.theme.isDark == !dark)
        #expect(controller.color(at: heading) == (dark ? BrandPalette.latte.magic : PaletteColor(hex: 0x123456)))
        let changedFont = try #require(controller.font(at: heading))
        #expect((NSFontManager.shared.weight(of: changedFont) < 9) == !dark)
        #expect(controller.text == Self.sample)
    }

    @Test func switchingThemesRestylesInPlace() {
        let controller = makeEditor(Self.sample, height: 400, dark: true)
        controller.mode = .raw
        #expect(controller.color(at: heading) == BrandPalette.mocha.magic)
        controller.theme = EditorTheme(light: .latte, dark: Self.neon)
        #expect(controller.text == Self.sample)
        #expect(controller.color(at: heading)?.description == "#123456")
        // The theme turned bold off for Raw headings.
        let font = controller.textView.textStorage?.attribute(.font, at: heading, effectiveRange: nil) as? NSFont
        #expect(NSFontManager.shared.weight(of: font ?? .systemFont(ofSize: 1)) < 9)
        controller.mode = .preview
        #expect(controller.color(at: heading)?.description == "#654321")
    }

    @Test func rawFollowsTheBrandRoles() {
        let controller = makeEditor(Self.sample, height: 400, dark: true)
        controller.mode = .raw
        let text = Self.sample as NSString
        #expect(controller.color(at: text.range(of: "title").location) == BrandPalette.mocha.link)
        #expect(controller.color(at: text.range(of: "Potions").location) == BrandPalette.mocha.string)
        #expect(controller.color(at: text.range(of: "- Ember").location) == BrandPalette.mocha.caret)
        #expect(controller.color(at: text.range(of: "**draught").location) == BrandPalette.mocha.caret)
        #expect(controller.color(at: 0) == BrandPalette.mocha.overlay1)
    }

    @Test func rawHighlightsTheCaretLine() {
        let controller = makeEditor(Self.sample, height: 400, dark: true)
        #expect(controller.textView.caretLineColor == nil)
        controller.mode = .raw
        #expect(controller.textView.caretLineColor != nil)
        controller.mode = .preview
        #expect(controller.textView.caretLineColor == nil)
    }

    @Test func caretAndSelectionUseTheEditorColors() {
        let controller = makeEditor(Self.sample, height: 400, dark: true)
        controller.theme = EditorTheme(light: .latte, dark: Self.neon)
        var caret: NSColor?
        controller.textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            caret = controller.textView.insertionPointColor.usingColorSpace(.sRGB)
        }
        #expect(caret.map { Int(($0.greenComponent * 255).rounded()) } == 255)
    }
}

@Suite struct MDXHighlighterTests {
    func tokens(_ source: String) -> [(MarkdownToken, String)] {
        let utf16 = Array(source.utf16)
        return MDXHighlighter.pieces(in: source).map {
            ($0.token, String(decoding: utf16[$0.range], as: UTF16.self))
        }
    }

    @Test func colorsTagsAttributesAndStrings() {
        let pieces = tokens(#"<Figure src="home.png" caption={note} wide />"#)
        #expect(pieces.map(\.0) == [.mdx, .mdxAttribute, .mdxString, .mdxAttribute, .mdxAttribute, .mdx])
        #expect(pieces.map(\.1) == ["<Figure", "src", "\"home.png\"", "caption", "wide", "/>"])
    }

    @Test func colorsImportsAndExports() {
        let pieces = tokens("import Figure from '../components/Figure.astro'\nexport const meta = {}")
        #expect(pieces.map(\.1) == ["import", "from", "'../components/Figure.astro'", "export", "const"])
    }

    @Test func colorsClosingTagsAndFragments() {
        let pieces = tokens("<Note>\nSome *text*\n</Note>\n<>")
        #expect(pieces.map(\.1) == ["<Note>", "</Note>", "<>"])
    }
}
#endif
