#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

@MainActor @Suite(.serialized) struct EditorSettingsTests {
    static let sample = EditorControllerTests.sample

    func makeController(_ text: String = sample, height: CGFloat = 300) -> (EditorController, NSWindow) {
        BrandFontTests.registerRepoFonts()
        let controller = EditorController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: height), styleMask: [.titled], backing: .buffered,
            defer: false)
        controller.scrollView.frame = window.contentView?.bounds ?? .zero
        window.contentView?.addSubview(controller.scrollView)
        controller.load(text, flavor: .markdown)
        window.displayIfNeeded()
        return (controller, window)
    }

    func font(_ controller: EditorController, at offset: Int) -> NSFont? {
        controller.textView.textStorage?.attribute(.font, at: offset, effectiveRange: nil) as? NSFont
    }

    @Test func fontsAndSizesComeFromSettings() {
        let (controller, _) = makeController()
        var theme = controller.theme
        theme.bodySize = 18
        theme.codeSize = 13
        theme.proseFamily = "Helvetica Neue"
        theme.setLineHeight(2.0)
        controller.theme = theme
        let body = (Self.sample as NSString).range(of: "Brews").location
        #expect(font(controller, at: body)?.familyName == "Helvetica Neue")
        #expect(font(controller, at: body)?.pointSize == 18)
        // Headings scale with the body.
        #expect(font(controller, at: 2)?.pointSize == (34 * 18 / 15.5).rounded())
        let code = (Self.sample as NSString).range(of: "let brew").location
        #expect(font(controller, at: code)?.familyName == "Geist Mono")
        #expect(font(controller, at: code)?.pointSize == 13)
        let style = controller.textView.textStorage?.attribute(.paragraphStyle, at: body, effectiveRange: nil)
        #expect(((style as? NSParagraphStyle)?.lineHeightMultiple ?? 0) > 1.5)
    }

    @Test func anUnknownFamilyFallsBackToGeist() {
        let font = BrandFont.ctFont(monospaced: false, size: 14, weight: 400, family: "Not A Real Font Family")
        #expect((CTFontCopyFamilyName(font) as String) == "Geist")
    }

    @Test func showingAllMarkersRevealsEveryBlock() {
        let (controller, _) = makeController()
        let bold = (Self.sample as NSString).range(of: "autumn").location
        #expect(font(controller, at: bold - 1)?.pointSize ?? 99 < 1)
        controller.revealsAllMarkers = true
        #expect(font(controller, at: bold - 1)?.pointSize == 15.5)
        #expect(controller.text == Self.sample)
        controller.revealsAllMarkers = false
        #expect(font(controller, at: bold - 1)?.pointSize ?? 99 < 1)
    }

    @Test func typewriterScrollingCentersTheCaret() {
        let text = (1...80).map { "Line \($0) of the ledger." }.joined(separator: "\n\n") + "\n"
        let (controller, _) = makeController(text)
        controller.typewriterScrolling = true
        let natural = controller.textView.frame.height
        let offset = (text as NSString).range(of: "Line 60 ").location
        controller.textView.setSelectedRange(NSRange(location: offset, length: 0))
        controller.textView.insertText("x", replacementRange: controller.textView.selectedRange())
        let clip = controller.scrollView.contentView.bounds
        let caret = controller.textView.firstRect(
            forCharacterRange: NSRange(location: offset, length: 0), actualRange: nil)
        let caretInWindow = controller.textView.window?.convertFromScreen(caret) ?? .zero
        let caretInClip = controller.scrollView.contentView.convert(caretInWindow, from: nil)
        #expect(abs(caretInClip.midY - clip.midY) < 30)

        // Typing at the end can still center the last line, and the page doesn't keep growing.
        let end = (controller.text as NSString).length
        controller.textView.setSelectedRange(NSRange(location: end, length: 0))
        for _ in 0..<3 { controller.textView.insertText("y", replacementRange: controller.textView.selectedRange()) }
        let grown = controller.textView.frame.height
        #expect(grown < natural + clip.height)
        controller.typewriterScrolling = false
        #expect(controller.textView.frame.height < grown)
    }

    @Test func imagesGoWhereSettingsSay() throws {
        let folder = URL(filePath: "/tmp/grimoire/notes/potions")
        #expect(
            EditorController.relativePath(from: folder, to: folder.appending(path: "assets/ink.png"))
                == "assets/ink.png")
        #expect(
            EditorController.relativePath(
                from: folder, to: URL(filePath: "/tmp/grimoire/assets/moon jar.png")) == "../../assets/moon%20jar.png")
        let (controller, _) = makeController()
        controller.fileURL = folder.appending(path: "ledger.md")
        #expect(controller.assetsFolder?.path(percentEncoded: false) == "/tmp/grimoire/notes/potions/assets/")
        controller.imageFolder = URL(filePath: "/tmp/grimoire/assets", directoryHint: .isDirectory)
        #expect(controller.imageLink(URL(filePath: "/tmp/grimoire/assets/ink.png")) == "![ink](../../assets/ink.png)")
    }
}
#endif
