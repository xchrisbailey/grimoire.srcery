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
import AppKit

@MainActor @Suite struct AltTextEditingTests {
    @Test func fillsInAltTextAsOneUndo() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "alt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let controller = EditorController()
        controller.fileURL = folder.appending(path: "page.md")
        let start = "# Page\n\n![pasted](assets/shot.png)\n\nMore ![](assets/shot.png) and ![keep](other.png)\n"
        controller.load(start, flavor: .markdown)
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

    @Test func pastedImagesAskForAltText() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "paste-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let controller = EditorController()
        controller.fileURL = folder.appending(path: "page.md")
        controller.load("", flavor: .markdown)
        var casts: [IntelligenceCast] = []
        controller.intelligenceEnabled = true
        controller.onIntelligence = { casts.append($0) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("grimoire-test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let image = NSImage(size: CGSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        pasteboard.setData(image.tiffRepresentation, forType: .tiff)
        #expect(controller.paste(from: pasteboard))
        #expect(controller.text.hasPrefix("![pasted-"))
        #expect(casts.count == 1 && casts[0].command == "alt")
        #expect(FileManager.default.fileExists(atPath: casts[0].source))
    }
}
#endif
