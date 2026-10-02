import Foundation
import Testing

@testable import GrimoireCore

@Suite struct PaletteColorTests {
    @Test func readsCSSHexForms() {
        #expect(PaletteColor(hex: "#1e1e2e") == PaletteColor(hex: 0x1e1e2e))
        #expect(PaletteColor(hex: "#fff") == PaletteColor(hex: 0xffffff))
        #expect(PaletteColor(hex: "1e1e2e") == nil)
        #expect(PaletteColor(hex: "#12345") == nil)
    }

    @Test func laysTranslucentColorsOverTheBackground() {
        let page = PaletteColor(hex: 0x000000)
        #expect(PaletteColor(hex: "#ffffff80", over: page) == PaletteColor(hex: 0x808080))
        #expect(PaletteColor(hex: "#ffff", over: page) == PaletteColor(hex: 0xffffff))
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(Theme.mocha)
        let decoded = try JSONDecoder().decode(Theme.self, from: data)
        #expect(decoded == Theme.mocha)
    }
}

@Suite struct BuiltInThemeTests {
    @Test func previewMatchesTheBrandBook() {
        let mocha = Theme.mocha
        #expect(mocha.style(.heading1, raw: false).color == nil)
        #expect(mocha.style(.listMarker, raw: false).color == BrandPalette.mocha.caret)
        #expect(mocha.style(.link, raw: false).color == BrandPalette.mocha.link)
        #expect(mocha.editor.caret == BrandPalette.mocha.caret)
    }

    @Test func rawMatchesTheBrandBook() {
        let latte = Theme.latte
        let palette = BrandPalette.latte
        #expect(latte.style(.heading2, raw: true) == TokenStyle(color: palette.magic, bold: true))
        #expect(latte.style(.listMarker, raw: true).color == palette.caret)
        #expect(latte.style(.emphasisMarker, raw: true).color == palette.caret)
        #expect(latte.style(.frontmatter, raw: true).color == palette.overlay1)
        #expect(latte.style(.frontmatterKey, raw: true).color == palette.link)
        #expect(latte.style(.frontmatterValue, raw: true).color == palette.string)
        #expect(latte.style(.quote, raw: true).color == palette.quote)
        #expect(latte.style(.mdx, raw: true).color == palette.sparkle)
        #expect(latte.style(.mdxAttribute, raw: true).color == palette.callout)
        #expect(latte.style(.syntaxMarker, raw: true).color == palette.overlay0)
    }
}

@Suite struct ClassicThemeTests {
    @Test func idsAndNamesAreUnique() {
        #expect(Set(Theme.builtIn.map(\.id)).count == Theme.builtIn.count)
        #expect(Set(Theme.builtIn.map(\.name)).count == Theme.builtIn.count)
    }

    @Test func darknessMatchesThePage() {
        for theme in Theme.builtIn {
            #expect(theme.isDark == (theme.palette.page.luminance < 0.2), "\(theme.name)")
        }
    }

    @Test func textIsReadableOnThePage() {
        for theme in Theme.builtIn {
            let palette = theme.palette
            let (light, dark) = (
                max(palette.ink.luminance, palette.page.luminance), min(palette.ink.luminance, palette.page.luminance)
            )
            #expect((light + 0.05) / (dark + 0.05) >= 4.5, "\(theme.name)")
        }
    }

    @Test func fillsRolesFromItsOwnPalette() {
        #expect(Theme.dracula.palette.magic.description == "#bd93f9")
        #expect(Theme.nord.palette.page.description == "#2e3440")
        #expect(Theme.solarizedLight.style(.link, raw: false).color?.description == "#268bd2")
        #expect(Theme.gruvboxDark.style(.keyword).color == Theme.gruvboxDark.palette.magic)
    }
}

@Suite struct LenientJSONTests {
    @Test func acceptsCommentsAndTrailingCommas() throws {
        let text = """
            // Theme
            {
              "name": "Ink // not a comment", /* block
              comment */
              "colors": { "editor.background": "#101010", },
              "tokenColors": [ { "scope": "comment", "settings": { "foreground": "#606060" } }, // last
              ],
            }
            """
        let json = try #require(try LenientJSON.parse(Data(text.utf8)) as? [String: Any])
        #expect(json["name"] as? String == "Ink // not a comment")
        #expect((json["colors"] as? [String: String])?["editor.background"] == "#101010")
        #expect((json["tokenColors"] as? [Any])?.count == 1)
    }

    @Test func rejectsWhatIsntJSON() {
        #expect(throws: ThemeImportError.notATheme) { try LenientJSON.parse(Data("not json".utf8)) }
    }
}

@Suite struct TextMateRulesTests {
    let rules = TextMateRules([
        ["settings": ["foreground": "#111111"]],
        ["scope": "markup", "settings": ["foreground": "#222222"]],
        ["scope": "markup.heading", "settings": ["foreground": "#333333", "fontStyle": "bold"]],
        ["scope": ["markup.heading.markdown", "  keyword "], "settings": ["foreground": "#444444"]],
        ["scope": "text.html.markdown markup.bold", "settings": ["fontStyle": "bold italic"]],
        ["scope": "source.css markup.italic", "settings": ["foreground": "#555555"]],
        ["scope": "markup.headings", "settings": ["foreground": "#666666"]],
    ])

    @Test func theMostSpecificRuleWinsEachSetting() throws {
        let match = try #require(rules.match(["text.html.markdown", "markup.heading.markdown"]))
        #expect(match.foreground == "#444444")
        #expect(match.fontStyle == "bold")
    }

    @Test func prefixesMatchWholeSegmentsOnly() throws {
        let match = try #require(rules.match(["text.html.markdown", "markup.heading"]))
        #expect(match.foreground == "#333333")
    }

    @Test func parentScopesMustMatch() throws {
        let bold = try #require(rules.match(["text.html.markdown", "markup.bold.markdown"]))
        #expect(bold.fontStyle == "bold italic")
        #expect(bold.foreground == "#222222")
        let italic = try #require(rules.match(["text.html.markdown", "markup.italic.markdown"]))
        #expect(italic.foreground == "#222222")
    }

    @Test func defaultsComeFromTheScopelessRule() {
        #expect(rules.defaultForeground == "#111111")
        #expect(rules.match(["source.swift", "comment"]) == nil)
    }
}

@Suite struct ThemeImportTests {
    static let darkTheme = """
        {
          "name": "Night Ink",
          "type": "dark",
          "colors": {
            "editor.background": "#101820",
            "editor.foreground": "#e0e0e0",
            "editor.selectionBackground": "#ffffff40",
            "editorCursor.foreground": "#ff0000",
            "sideBar.background": "#0c1218",
            "textLink.foreground": "#00aaff",
          },
          "tokenColors": [
            { "scope": "comment", "settings": { "foreground": "#707070", "fontStyle": "italic" } },
            { "scope": ["keyword", "storage.type"], "settings": { "foreground": "#c080ff" } },
            { "scope": "string", "settings": { "foreground": "#80ff80" } },
            { "scope": "constant.numeric", "settings": { "foreground": "#ffa040" } },
            { "scope": "markup.heading", "settings": { "foreground": "#ff6080", "fontStyle": "bold" } },
            { "scope": "markup.italic", "settings": { "fontStyle": "italic" } },
            { "scope": "markup.inline.raw", "settings": { "foreground": "#40e0d0" } },
          ],
        }
        """

    func convert(_ text: String, fileName: String = "night-ink.json") throws -> Theme {
        ThemeImport.convert(try VSCodeTheme(data: Data(text.utf8), fallbackName: "Fallback"), fileName: fileName)
    }

    @Test func mapsWorkbenchColorsToBrandRoles() throws {
        let theme = try convert(Self.darkTheme)
        #expect(theme.name == "Night Ink")
        #expect(theme.isDark)
        #expect(theme.origin == .imported(fileName: "night-ink.json"))
        #expect(theme.palette.page.description == "#101820")
        #expect(theme.palette.ink.description == "#e0e0e0")
        #expect(theme.palette.sidebar.description == "#0c1218")
        #expect(theme.palette.link.description == "#00aaff")
        #expect(theme.palette.magic.description == "#c080ff")
        #expect(theme.palette.string.description == "#80ff80")
        #expect(theme.palette.caret.description == "#ffa040")
        #expect(theme.palette.overlay1.description == "#707070")
        #expect(theme.editor.caret.description == "#ff0000")
        // #ffffff at 25% over #101820.
        #expect(
            theme.editor.selection
                == PaletteColor(hex: 0x101820).mixed(with: PaletteColor(hex: 0xffffff), amount: 64.0 / 255))
    }

    @Test func mapsTokenColorsToMarkdown() throws {
        let theme = try convert(Self.darkTheme)
        #expect(
            theme.style(.heading1, raw: true)
                == TokenStyle(
                    color: PaletteColor(hex: 0xff6080), bold: true, italic: false, underline: false,
                    strikethrough: false))
        #expect(theme.style(.heading3, raw: false).color?.description == "#ff6080")
        #expect(theme.style(.inlineCode, raw: true).color?.description == "#40e0d0")
        #expect(theme.style(.italic, raw: true).italic == true)
        #expect(theme.style(.comment).italic == true)
        #expect(theme.style(.keyword).color?.description == "#c080ff")
    }

    @Test func fillsGapsFromCatppuccin() throws {
        let theme = try convert(##"{ "name": "Bare", "type": "light", "colors": {} }"##)
        #expect(!theme.isDark)
        #expect(theme.palette.page == BrandPalette.latte.page)
        #expect(theme.palette.magic == BrandPalette.latte.magic)
        #expect(theme.style(.heading1, raw: true).color == BrandPalette.latte.magic)
    }

    @Test func guessesAppearanceFromTheBackground() throws {
        let theme = try convert(##"{ "colors": { "editor.background": "#fdf6e3" } }"##)
        #expect(!theme.isDark)
        #expect(theme.name == "Fallback")
    }

    @Test func mergesAnIncludedParent() throws {
        let parent = """
            { "name": "Parent", "type": "dark",
              "colors": { "editor.background": "#000000", "editor.foreground": "#ffffff" },
              "tokenColors": [{ "scope": "string", "settings": { "foreground": "#00ff00" } }] }
            """
        let child = ##"{ "name": "Child", "include": "./parent.json", "colors": { "editor.background": "#202020" } }"##
        let source = try VSCodeTheme(data: Data(child.utf8), fallbackName: "x") { path in
            path == "./parent.json" ? Data(parent.utf8) : nil
        }
        let theme = ThemeImport.convert(source, fileName: "child.json")
        #expect(theme.name == "Child")
        #expect(theme.isDark)
        #expect(theme.palette.page.description == "#202020")
        #expect(theme.palette.ink.description == "#ffffff")
        #expect(theme.palette.string.description == "#00ff00")
    }

    @Test func readsAVsixExtension() throws {
        let scratch = try Scratch()
        let root = try scratch.folder("ext/extension")
        try scratch.file(
            "ext/extension/package.json",
            """
            { "contributes": { "themes": [
              { "label": "Night Ink", "uiTheme": "vs-dark", "path": "./themes/night.json" },
              { "label": "Day Ink", "uiTheme": "vs", "path": "./themes/day.json" } ] } }
            """)
        try scratch.file("ext/extension/themes/night.json", Self.darkTheme)
        try scratch.file("ext/extension/themes/day.json", ##"{ "include": "./base.json" }"##)
        try scratch.file("ext/extension/themes/base.json", ##"{ "colors": { "editor.background": "#fafafa" } }"##)
        let vsix = scratch.url.appending(path: "night-ink.vsix")
        let zip = Process()
        zip.executableURL = URL(filePath: "/usr/bin/zip")
        zip.currentDirectoryURL = root.deletingLastPathComponent()
        zip.arguments = ["-qr", vsix.path(percentEncoded: false), "extension"]
        try zip.run()
        zip.waitUntilExit()

        let themes = try ThemeImport.themes(from: vsix)
        #expect(themes.map(\.name) == ["Night Ink", "Day Ink"])
        #expect(themes.map(\.isDark) == [true, false])
        #expect(themes[1].palette.page.description == "#fafafa")
        #expect(themes.allSatisfy { $0.origin == .imported(fileName: "night-ink.vsix") })
    }

    @Test func explainsFilesThatArentThemes() throws {
        let scratch = try Scratch()
        let notes = try scratch.file("notes.json", "[1, 2, 3]")
        #expect(throws: ThemeImportError.notATheme) { try ThemeImport.themes(from: notes) }
        let empty = try scratch.file("empty.vsix", "PK\u{3}\u{4}")
        #expect(throws: ThemeImportError.unreadable("empty.vsix")) { try ThemeImport.themes(from: empty) }
    }
}

@Suite struct ZipArchiveTests {
    @Test func readsStoredAndDeflatedEntries() throws {
        let scratch = try Scratch()
        try scratch.file("pack/small.txt", "ink")
        try scratch.file("pack/large.txt", String(repeating: "grimoire ", count: 2_000))
        let archive = scratch.url.appending(path: "pack.zip")
        let zip = Process()
        zip.executableURL = URL(filePath: "/usr/bin/zip")
        zip.currentDirectoryURL = scratch.url
        zip.arguments = ["-qr", archive.path(percentEncoded: false), "pack"]
        try zip.run()
        zip.waitUntilExit()

        let reader = try ZipArchive(data: Data(contentsOf: archive))
        #expect(Set(reader.paths).isSuperset(of: ["pack/small.txt", "pack/large.txt"]))
        #expect(try reader.contents(of: "pack/small.txt") == Data("ink".utf8))
        let large = try #require(try reader.contents(of: "pack/large.txt"))
        #expect(String(decoding: large, as: UTF8.self) == String(repeating: "grimoire ", count: 2_000))
        #expect(try reader.contents(of: "missing") == nil)
    }

    @Test func rejectsWhatIsntAZip() {
        #expect(throws: ZipArchive.ZipError.notAZip) { try ZipArchive(data: Data("hello".utf8)) }
    }
}

@MainActor @Suite struct ThemeLibraryTests {
    func makeLibrary(_ scratch: Scratch) -> (ThemeLibrary, UserDefaults) {
        let defaults = UserDefaults(suiteName: "grimoire-tests-\(UUID().uuidString)")!
        return (ThemeLibrary(folder: scratch.url.appending(path: "Themes"), defaults: defaults), defaults)
    }

    @Test func startsWithTheBuiltInThemes() throws {
        let (library, _) = makeLibrary(try Scratch())
        #expect(library.themes.prefix(2).map(\.name) == ["Catppuccin Mocha", "Catppuccin Latte"])
        #expect(library.themes.contains(.dracula) && library.themes.contains(.solarizedLight))
        #expect(library.lightTheme == .latte)
        #expect(library.darkTheme == .mocha)
        #expect(library.appearance == .system)
    }

    @Test func importsSavesAndSelectsATheme() throws {
        let scratch = try Scratch()
        let file = try scratch.file("night-ink.json", ThemeImportTests.darkTheme)
        let (library, defaults) = makeLibrary(scratch)
        let imported = try library.importThemes(from: file)
        #expect(imported.count == 1)
        #expect(library.darkTheme.name == "Night Ink")
        #expect(library.lightTheme == .latte)

        // A second library reading the same folder and settings sees it too.
        let reopened = ThemeLibrary(folder: scratch.url.appending(path: "Themes"), defaults: defaults)
        #expect(reopened.imported.map(\.name) == ["Night Ink"])
        #expect(reopened.darkTheme.name == "Night Ink")

        // Importing the same file again replaces it rather than adding a copy.
        try library.importThemes(from: file)
        #expect(library.imported.count == 1)
    }

    @Test func removingAThemeFallsBackToCatppuccin() throws {
        let scratch = try Scratch()
        let file = try scratch.file("night-ink.json", ThemeImportTests.darkTheme)
        let (library, _) = makeLibrary(scratch)
        let theme = try #require(try library.importThemes(from: file).first)
        library.remove(theme.id)
        #expect(library.imported.isEmpty)
        #expect(library.darkTheme == .mocha)
        library.remove(Theme.mocha.id)
        #expect(library.themes == Theme.builtIn)
    }

    @Test func remembersTheChoices() throws {
        let scratch = try Scratch()
        let (library, defaults) = makeLibrary(scratch)
        library.setAppearance(.dark)
        library.setLightTheme(Theme.mocha.id)
        let reopened = ThemeLibrary(folder: scratch.url.appending(path: "Themes"), defaults: defaults)
        #expect(reopened.appearance == .dark)
        #expect(reopened.lightTheme == .mocha)
    }
}
