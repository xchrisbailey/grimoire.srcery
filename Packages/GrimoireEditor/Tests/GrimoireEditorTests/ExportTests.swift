#if os(macOS)
import AppKit
import GrimoireCore
import PDFKit
import Testing

@testable import GrimoireEditor

@MainActor @Suite(.serialized) struct ExportTests {
    static let sample = """
        ---
        title: Potions
        ---

        import Figure from './Figure'

        # Potion ledger

        Brews from the **autumn** batch, see [runes](runes.md) & 3 < 4.

        - [ ] Ember draught
        - [x] Moonwater tincture

        > [!NOTE]
        > Keep the volatile ones up high.

        | Potion | Strength |
        | --- | ---: |
        | Ember | 3 |
        | Moonwater | 12 |

        ```swift
        let brew = "ink" // stir
        ```

        ![Ink](assets/ink.png)

        """

    func writeSample() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "grimoire-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appending(path: "assets"), withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 120, height: 60), flipped: false) { rect in
            NSColor.systemPurple.setFill()
            rect.fill()
            return true
        }
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: folder.appending(path: "assets/ink.png"))
        let file = folder.appending(path: "ledger.mdx")
        try Data(Self.sample.utf8).write(to: file)
        return file
    }

    @Test func rendersASelfContainedPage() throws {
        BrandFontTests.registerRepoFonts()
        let file = try writeSample()
        let html = DocumentExport.html(markdown: Self.sample, fileURL: file, title: "ledger", style: .theme(.mocha))
        #expect(html.contains("<h1 id=\"potion-ledger\">Potion ledger</h1>"))
        #expect(html.contains("<strong>autumn</strong>"))
        #expect(html.contains("&amp; 3 &lt; 4"))
        #expect(!html.contains("title: Potions"))
        #expect(!html.contains("import Figure"))
        #expect(html.contains("<input type=\"checkbox\" disabled checked />"))
        #expect(html.contains("callout-note"))
        #expect(html.contains("<th style=\"text-align: right\">Strength</th>"))
        #expect(html.contains("color: #cba6f7\">let</span>"))
        #expect(html.contains("src=\"data:image/png;base64,"))
        #expect(html.contains("@font-face"))
        #expect(html.contains("background: #1e1e2e"))
    }

    @Test func breaksPagesBetweenBlocks() {
        let pages = PagePrinter.pageBreaks(
            height: 2_000, blockTops: [0, 300, 700, 1_100, 1_500, 1_900], pageHeight: 800)
        #expect(pages.map(\.lowerBound) == [0, 700, 1_500])
        #expect(pages.last?.upperBound == 2_000)
        // A block taller than a page is cut at the page's foot.
        let tall = PagePrinter.pageBreaks(height: 2_000, blockTops: [0], pageHeight: 800)
        #expect(tall.map(\.lowerBound) == [0, 800, 1_600])
    }

    @Test func printStyleIsDarkOnWhite() throws {
        BrandFontTests.registerRepoFonts()
        let html = DocumentExport.html(
            markdown: "# Ink\n", fileURL: nil, title: "ink", style: .print, embedFonts: false, paged: true)
        #expect(html.contains("background: #ffffff"))
        #expect(html.contains("<body class=\"paged\">"))
        #expect(!html.contains("@font-face"))
    }
}
#endif
