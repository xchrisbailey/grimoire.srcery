#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

@MainActor @Suite(.serialized) struct FindTests {
    static let sample = """
        # Potions

        Ink of recall. More ink, more ink-wells.

        ## Storage

        Keep the ink dry.

        """

    // swiftlint:disable:next large_tuple
    func makeController(_ text: String = sample) -> (EditorController, EditorProxy, NSWindow) {
        BrandFontTests.registerRepoFonts()
        let controller = EditorController()
        let proxy = EditorProxy()
        controller.proxy = proxy
        proxy.controller = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered,
            defer: false)
        controller.scrollView.frame = window.contentView?.bounds ?? .zero
        window.contentView?.addSubview(controller.scrollView)
        controller.load(text, flavor: .markdown)
        return (controller, proxy, window)
    }

    func selected(_ controller: EditorController) -> String { controller.selectedText }

    @Test func findsAndWrapsAround() {
        let (controller, proxy, _) = makeController()
        proxy.showFind()
        proxy.findQuery = "ink"
        #expect(proxy.matchCount == 4)
        proxy.findNext()
        #expect(selected(controller) == "Ink")
        #expect(proxy.currentMatch == 0)
        proxy.findNext()
        proxy.findNext()
        proxy.findNext()
        #expect(proxy.currentMatch == 3)
        proxy.findNext()
        #expect(proxy.currentMatch == 0)
        proxy.findPrevious()
        #expect(proxy.currentMatch == 3)
        proxy.caseSensitive = true
        #expect(proxy.matchCount == 3)
        proxy.findQuery = "in"
        #expect(proxy.matchCount == 3)
        proxy.wholeWord = true
        #expect(proxy.matchCount == 0)
    }

    @Test func seedsTheQueryFromTheSelection() {
        let (controller, proxy, _) = makeController()
        controller.textView.setSelectedRange((Self.sample as NSString).range(of: "recall"))
        proxy.showFind(replace: true)
        #expect(proxy.findQuery == "recall")
        #expect(proxy.isFindVisible && proxy.showsReplace)
        proxy.hideFind()
        #expect(!proxy.isFindVisible)
        #expect(controller.findMatches.isEmpty)
    }

    @Test func replacesOneThenAllInOneUndo() {
        let (controller, proxy, _) = makeController()
        proxy.showFind(replace: true)
        proxy.findQuery = "ink"
        proxy.replacement = "quill"
        proxy.findNext()
        proxy.replaceCurrent()
        #expect(controller.text.contains("quill of recall"))
        #expect(proxy.matchCount == 3)
        // Each user action is its own undo step; let the run loop close this one.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        proxy.replaceAll()
        #expect(!controller.text.lowercased().contains("ink"))
        #expect(controller.text.contains("quill-wells"))
        controller.textView.undoManager?.undo()
        #expect(controller.text.contains("ink-wells"))
        #expect(controller.text.contains("quill of recall"))
    }

    @Test func regexReplacementsUseGroups() {
        let (controller, proxy, _) = makeController()
        var snapshots = 0
        controller.onBeforeLargeEdit = { _ in snapshots += 1 }
        proxy.showFind(replace: true)
        proxy.regex = true
        proxy.findQuery = "(\\w+)-wells"
        proxy.replacement = "$1 pots"
        proxy.replaceAll()
        #expect(controller.text.contains("more ink pots."))
        #expect(snapshots == 1)
        proxy.findQuery = "("
        #expect(proxy.search.isInvalid)
        #expect(proxy.matchCount == 0)
    }

    @Test func theFindMenuDrivesTheBar() {
        let (controller, proxy, _) = makeController()
        controller.textView.setSelectedRange((Self.sample as NSString).range(of: "dry"))
        let item = NSMenuItem(
            title: "Find", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "")
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        controller.textView.performFindPanelAction(item)
        #expect(proxy.isFindVisible)
        #expect(proxy.findQuery == "dry")
        #expect(controller.textView.validateUserInterfaceItem(item))
        item.tag = NSTextFinder.Action.showReplaceInterface.rawValue
        controller.textView.performFindPanelAction(item)
        #expect(proxy.showsReplace)
    }

    @Test func listsHeadingsAndJumpsToThem() {
        let (controller, proxy, _) = makeController()
        #expect(proxy.headings.map(\.title) == ["Potions", "Storage"])
        #expect(proxy.headings.map(\.level) == [1, 2])
        let storage = proxy.headings[1]
        proxy.reveal(NSRange(location: storage.offset, length: 0))
        #expect(controller.textView.selectedRange().location == (Self.sample as NSString).range(of: "Storage").location)
    }

    @Test func restoringTextIsOneUndoableEdit() {
        let (controller, proxy, _) = makeController()
        proxy.replaceText("# Restored\n", actionName: "Restore Version")
        #expect(controller.text == "# Restored\n")
        controller.textView.undoManager?.undo()
        #expect(controller.text == Self.sample)
    }

    @Test func castsSpellsAtTheCaret() throws {
        let (controller, proxy, _) = makeController()
        let offset = (Self.sample as NSString).range(of: "Keep").location
        controller.textView.setSelectedRange(NSRange(location: offset, length: 0))
        let quote = try #require(Spellbook.standard.first { $0.id == "quote" })
        proxy.cast(quote)
        #expect(controller.text.contains("> Keep the ink dry."))
    }
}
#endif
