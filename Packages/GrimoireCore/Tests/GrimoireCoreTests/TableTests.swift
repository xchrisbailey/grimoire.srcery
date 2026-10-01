import Foundation
import Testing

@testable import GrimoireCore

@Suite struct MarkdownTableTests {
    @Test func parsesCellsAlignmentsAndEscapes() throws {
        let table = try #require(
            MarkdownTable(parsing: "| Name | Qty | Note |\n|:--|--:|:-:|\n| Ember | 2 | a \\| b |\n| `x|y` | 10 |"))
        #expect(table.rows == [["Name", "Qty", "Note"], ["Ember", "2", "a \\| b"], ["`x|y`", "10", ""]])
        #expect(table.alignments == [.left, .right, .center])
        #expect(MarkdownTable(parsing: "a | b\n--- | ---\nc | d")?.rows == [["a", "b"], ["c", "d"]])
        #expect(MarkdownTable(parsing: "| a |\n| b |") == nil)
    }

    @Test func writesAlignedColumns() {
        let table = MarkdownTable(
            rows: [["Potion", "Qty"], ["Moonwater", "12"], ["Ink", "3"]], alignments: [.none, .right])
        #expect(
            table.markdown == """
                | Potion    | Qty |
                | --------- | --: |
                | Moonwater |  12 |
                | Ink       |   3 |
                """)
        let center = MarkdownTable(rows: [["a"], ["b"]], alignments: [.center])
        #expect(center.markdown == "|  a  |\n| :-: |\n|  b  |")
    }

    @Test func roundTripsItsOwnOutput() throws {
        let table = MarkdownTable(rows: [["日本", "x"], ["🧪", "longer cell"]])
        let reparsed = try #require(MarkdownTable(parsing: table.markdown))
        #expect(reparsed == table)
        #expect(
            table.markdown.components(separatedBy: "\n").map { MarkdownTable.displayWidth($0) }.allSatisfy {
                $0 == MarkdownTable.displayWidth(table.markdown.components(separatedBy: "\n")[0])
            })
    }

    @Test func rowsAndColumns() {
        var table = MarkdownTable.empty(columns: 2, bodyRows: 1)
        table.insertRow(at: 2)
        table.insertColumn(at: 1)
        #expect(table.rowCount == 3)
        #expect(table.columnCount == 3)
        table.removeRow(at: 0)
        #expect(table.rowCount == 3)
        table.removeColumn(at: 0)
        table.removeColumn(at: 0)
        table.removeColumn(at: 0)
        #expect(table.columnCount == 1)
    }

    @Test func pastesTSVAndCSV() throws {
        let tsv = try #require(MarkdownTable(delimited: "Name\tQty\nEmber\t2\nInk | well\t3\n"))
        #expect(tsv.rows == [["Name", "Qty"], ["Ember", "2"], ["Ink \\| well", "3"]])
        let csv = try #require(MarkdownTable(delimited: "a,b\n\"x, y\",\"say \"\"hi\"\"\"", csv: true))
        #expect(csv.rows == [["a", "b"], ["x, y", "say \"hi\""]])
        #expect(MarkdownTable(delimited: "just one line") == nil)
    }
}

/// Text with `‸` marking the caret.
private func run(_ marked: String, _ action: (BlockEditing) -> TextEdit?) -> String? {
    let range = (marked as NSString).range(of: "‸")
    let text = (marked as NSString).replacingCharacters(in: range, with: "")
    let editing = BlockEditing(text: text, index: BlockIndex(text: text), selection: range.location..<range.location)
    guard let edit = action(editing) else { return nil }
    let result = edit.applied(to: text) as NSString
    return result.replacingCharacters(in: NSRange(location: edit.selection.lowerBound, length: 0), with: "‸")
}

@Suite struct TableEditingTests {
    let table = "| a | b |\n| --- | --- |\n| 1 | 2 |\n"

    @Test func findsTheCaretsCell() throws {
        let text = "Intro\n\n| Name | Qty |\n| --- | --- |\n| Ember | 2 |\n"
        let offset = (text as NSString).range(of: "mber").location
        let editing = BlockEditing(text: text, index: BlockIndex(text: text), selection: offset..<offset)
        #expect(editing.tableCell == TableCell(block: 1, row: 1, column: 0, offset: 1))
    }

    @Test func tabMovesThroughCellsAndAddsARow() {
        #expect(
            run("| a‸ | b |\n| --- | --- |\n| 1 | 2 |\n", { $0.moveToNextCell(backward: false) })
                == "| a   | b‸   |\n| --- | --- |\n| 1   | 2   |\n")
        #expect(
            run("| a | b |\n| --- | --- |\n| 1 | 2‸ |\n", { $0.moveToNextCell(backward: false) })
                == "| a   | b   |\n| --- | --- |\n| 1   | 2   |\n| ‸    |     |\n")
        #expect(
            run("| a | b |\n| --- | --- |\n| ‸1 | 2 |\n", { $0.moveToNextCell(backward: true) })
                == "| a   | b‸   |\n| --- | --- |\n| 1   | 2   |\n")
    }

    @Test func enterGoesDownAndAddsRowsAtTheEnd() {
        #expect(
            run("| a‸ | b |\n| --- | --- |\n| 1 | 2 |\n", { $0.tableNewline() })
                == "| a   | b   |\n| --- | --- |\n| 1‸   | 2   |\n")
        #expect(
            run("| a | b |\n| --- | --- |\n| 1 | 2‸ |\n", { $0.tableNewline() })
                == "| a   | b   |\n| --- | --- |\n| 1   | 2   |\n|     | ‸    |\n")
    }

    @Test func rowColumnAndAlignmentChanges() {
        #expect(
            run("| a | b |\n| --- | --- |\n| 1‸ | 2 |\n", { $0.changeTable(.insertRowAbove) })
                == "| a   | b   |\n| --- | --- |\n| ‸    |     |\n| 1   | 2   |\n")
        #expect(
            run("| a | b |\n| --- | --- |\n| 1‸ | 2 |\n", { $0.changeTable(.deleteRow) })
                == "| a‸   | b   |\n| --- | --- |\n")
        #expect(
            run("| a‸ | b |\n| --- | --- |\n| 1 | 2 |\n", { $0.changeTable(.insertColumnRight) })
                == "| a   | ‸    | b   |\n| --- | --- | --- |\n| 1   |     | 2   |\n")
        #expect(
            run("| a‸ | b |\n| --- | --- |\n| 1 | 2 |\n", { $0.changeTable(.deleteColumn) })
                == "| b‸   |\n| --- |\n| 2   |\n")
        #expect(
            run("| a | b‸ |\n| --- | --- |\n| 1 | 2 |\n", { $0.changeTable(.align(.right)) })
                == "| a   |   b‸ |\n| --- | --: |\n| 1   |   2 |\n")
    }

    @Test func formatTableKeepsTheCaret() {
        #expect(
            run("| Name | Q |\n|-|-|\n| Moon‸water | 12 |", { $0.formatTable() })
                == "| Name      | Q   |\n| --------- | --- |\n| Moon‸water | 12  |")
    }

    @Test func outsideATableNothingHappens() {
        #expect(run("Para‸", { $0.moveToNextCell(backward: false) }) == nil)
    }
}

@Suite struct TableFormatOnLeaveTests {
    @Test func formatsATableAboveTheCaret() {
        let text = "| a | b |\n|-|-|\n| 1 | 2 |\n\nAfter"
        let caret = (text as NSString).range(of: "After").location + 2
        let editing = BlockEditing(text: text, index: BlockIndex(text: text), selection: caret..<caret)
        let edit = editing.formatTable(block: 0)
        let result = edit.map { $0.applied(to: text) }
        #expect(result == "| a   | b   |\n| --- | --- |\n| 1   | 2   |\n\nAfter")
        #expect(edit.map { (result! as NSString).substring(from: $0.selection.lowerBound) } == "ter")
        let tidy = BlockEditing(text: result!, index: BlockIndex(text: result!), selection: 0..<0)
        #expect(tidy.formatTable(block: 0) == nil)
    }
}
