#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

@MainActor @Suite(.serialized) struct TableEditorTests {
    func makeController(_ text: String = "") -> EditorController {
        BrandFontTests.registerRepoFonts()
        let controller = EditorController()
        controller.defaults = UserDefaults(suiteName: "grimoire-tests-\(UUID())") ?? .standard
        controller.textView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        controller.load(text, flavor: .markdown)
        controller.textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return controller
    }

    func type(_ string: String, into controller: EditorController) {
        for character in string {
            controller.textView.insertText(String(character), replacementRange: controller.textView.selectedRange())
        }
    }

    func press(_ selector: Selector, in controller: EditorController) {
        controller.textView.doCommand(by: selector)
    }

    /// The "done when" for #22: a 10×20 table built and filled without typing a pipe, saved as
    /// clean, aligned markdown.
    @Test func buildsATenByTwentyTableWithoutTypingAPipe() throws {
        let controller = makeController()
        type("/table", into: controller)
        press(#selector(NSResponder.insertNewline(_:)), in: controller)
        // Back to the header's first cell, then widen to ten columns.
        controller.textView.setSelectedRange(NSRange(location: 2, length: 0))
        for _ in 0..<8 { controller.changeTable(.insertColumnRight, actionName: "") }
        controller.textView.setSelectedRange(NSRange(location: 2, length: 0))
        // Header plus twenty body rows; Tab moves along and adds rows at the end.
        for row in 0...20 {
            for column in 0..<10 {
                let cell = row == 0 ? "Head \(column)" : "r\(row)c\(column)"
                // The starting cells hold "Column 1/2"; select them so typing replaces them.
                selectCellText(controller)
                controller.textView.insertText(cell, replacementRange: controller.textView.selectedRange())
                if !(row == 20 && column == 9) { press(#selector(NSResponder.insertTab(_:)), in: controller) }
            }
        }
        #expect(!controller.text.contains("Column"))
        let formatted = try #require(controller.editing.formatTable())
        controller.apply(formatted)
        let table = try #require(MarkdownTable(parsing: controller.text.trimmingCharacters(in: .newlines)))
        #expect(table.columnCount == 10)
        #expect(table.rowCount == 21)
        #expect(table.rows[20][9] == "r20c9")
        let lines = controller.text.trimmingCharacters(in: .newlines).components(separatedBy: "\n")
        #expect(Set(lines.map(\.count)).count == 1)
        #expect(lines.allSatisfy { $0.hasPrefix("| ") && $0.hasSuffix(" |") })
    }

    private func selectCellText(_ controller: EditorController) {
        guard let cell = controller.editing.tableCell else { return }
        let text = controller.textView.string as NSString
        let caret = controller.textView.selectedRange().location
        let line = text.lineRange(for: NSRange(location: caret, length: 0))
        let lineText = text.substring(with: line).trimmingCharacters(in: .newlines)
        let range = MarkdownTable.cellRanges(in: lineText)[cell.column]
        let content = (lineText as NSString).substring(with: NSRange(location: range.lowerBound, length: range.count))
        let leading = content.prefix { $0 == " " }.count
        let length = content.trimmingCharacters(in: .whitespaces).utf16.count
        controller.textView.setSelectedRange(
            NSRange(location: line.location + range.lowerBound + leading, length: length))
    }

    @Test func enterInTheLastRowAddsARow() {
        let controller = makeController("| a | b |\n| --- | --- |\n| 1 | 2 |")
        press(#selector(NSResponder.insertNewline(_:)), in: controller)
        #expect(controller.text == "| a   | b   |\n| --- | --- |\n| 1   | 2   |\n|     |     |")
        #expect(controller.editing.tableCell?.row == 2)
    }

    @Test func pastingSpreadsheetCellsMakesATable() {
        let controller = makeController("Intro\n\n")
        let board = NSPasteboard(name: NSPasteboard.Name("grimoire-test-\(UUID())"))
        board.clearContents()
        board.setString("Potion\tQty\nInk\t3\n", forType: .string)
        #expect(controller.paste(from: board))
        board.releaseGlobally()
        #expect(controller.text == "Intro\n\n| Potion | Qty |\n| ------ | --- |\n| Ink    | 3   |\n")
    }

    @Test func leavingATableTidiesIt() async throws {
        let controller = makeController("| a | b |\n|-|-|\n| 1 | 2 |\n\nAfter")
        controller.textView.setSelectedRange(NSRange(location: 2, length: 0))
        controller.textView.setSelectedRange(NSRange(location: (controller.text as NSString).length, length: 0))
        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.text == "| a   | b   |\n| --- | --- |\n| 1   | 2   |\n\nAfter")
        #expect(controller.textView.selectedRange().location == (controller.text as NSString).length)
    }

    @Test func gridHidesPipesButKeepsThem() {
        let controller = makeController("| a | b |\n| --- | --- |\n| 1 | 2 |\n\nPara")
        let font = controller.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.pointSize ?? 99 < 1)
        let kern = controller.textView.textStorage?.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat
        #expect((kern ?? 0) > 0)
        let decoration = controller.textView.textStorage?.attribute(.grimoireDecoration, at: 2, effectiveRange: nil)
        if case .tableRow(let edges, let isHeader, _) = (decoration as? LineDecoration)?.kind {
            #expect(edges.count == 3)
            #expect(isHeader)
        } else {
            Issue.record("No table row decoration")
        }
        controller.mode = .raw
        let rawFont = controller.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(rawFont?.pointSize == 14)
    }
}
#endif

#if os(macOS)
@MainActor @Suite struct TableTypingSpeedTests {
    @Test func typingInABigTableIsQuick() {
        BrandFontTests.registerRepoFonts()
        let table = MarkdownTable(rows: (0...20).map { row in (0..<10).map { "r\(row)c\($0)" } })
        let controller = EditorController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled], backing: .buffered,
            defer: false)
        controller.scrollView.frame = window.contentView?.bounds ?? .zero
        window.contentView?.addSubview(controller.scrollView)
        controller.load(table.markdown + "\n", flavor: .markdown)
        window.displayIfNeeded()
        let offset = (controller.text as NSString).range(of: "r10c5").location + 2
        controller.textView.setSelectedRange(NSRange(location: offset, length: 0))
        let clock = ContinuousClock()
        var slowest = Duration.zero
        for _ in 0..<10 {
            slowest = max(
                slowest,
                clock.measure {
                    controller.textView.insertText("x", replacementRange: controller.textView.selectedRange())
                })
        }
        print("Slowest keystroke in a 10×21 table: \(slowest)")
        #expect(slowest < budget(.milliseconds(50)))
    }
}
#endif
