import Foundation
import Testing

@testable import GrimoireEditor

@Suite struct ImageLinkTests {
    @Test func findsImagesAndTheirFiles() {
        let text = "Intro ![](assets/a%20b.png) and ![Old](/tmp/c.png \"Title\")\n\n![x](https://example.com/d.png)"
        let links = ImageLink.all(in: text)
        #expect(links.map(\.destination) == ["assets/a%20b.png", "/tmp/c.png", "https://example.com/d.png"])
        #expect(links[1].alt == "Old")
        let folder = URL(filePath: "/notes/")
        #expect(links[0].fileURL(relativeTo: folder)?.path == "/notes/assets/a b.png")
        #expect(links[1].fileURL(relativeTo: folder)?.path == "/tmp/c.png")
        #expect(links[2].fileURL(relativeTo: folder) == nil)
    }

    @Test func findsTheImageAtTheCaret() {
        let text = "# Page\n\n![](a.png)\n\nText"
        #expect(ImageLink.at(10, in: text)?.destination == "a.png")
        #expect(ImageLink.at(18, in: text)?.destination == "a.png")
        #expect(ImageLink.at(19, in: text) == nil)
        #expect(ImageLink.at(2, in: text) == nil)
    }

    @Test func altTextStaysInsideTheBrackets() {
        #expect(ImageLink.escapedAlt("A [draft]\nnote") == "A (draft) note")
    }
}

#if os(macOS)
@MainActor @Suite struct AltTextEditingTests {
    @Test func fillsInAltTextAsOneUndo() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "alt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let start = "# Page\n\n![pasted](assets/shot.png)\n\nMore ![](assets/shot.png) and ![keep](other.png)\n"
        let controller = makeEditor(start)
        controller.fileURL = folder.appending(path: "page.md")
        let image = folder.appending(path: "assets/shot.png")
        #expect(controller.setAltText("A [red] circle", forImageAt: image))
        #expect(
            controller.text
                == "# Page\n\n![A (red) circle](assets/shot.png)\n\n"
                + "More ![A (red) circle](assets/shot.png) and ![keep](other.png)\n"
        )
        controller.textView.undoManager?.undo()
        #expect(controller.text == start)
        #expect(!controller.setAltText("Nope", forImageAt: folder.appending(path: "missing.png")))
    }
}
#endif
