import Foundation

/// Where the caret sits in a table.
public struct TableCell: Equatable, Sendable {
    /// The table's block.
    public var block: Int
    /// 0 for the header row, then the body rows (the delimiter row isn't counted).
    public var row: Int
    public var column: Int
    /// The caret's offset into the cell's trimmed text.
    public var offset: Int

    public init(block: Int, row: Int, column: Int, offset: Int) {
        self.block = block
        self.row = row
        self.column = column
        self.offset = offset
    }
}

/// Table editing as text edits: moving between cells, adding and removing rows and
/// columns, alignment, and re-padding so the pipes line up.
extension BlockEditing {
    /// The table cell holding the caret, if the caret is in a table.
    public var tableCell: TableCell? {
        guard let block = block(at: caret), index.blocks[block].kind == .table else { return nil }
        let source = NSRange(index.sourceRange(of: block))
        let line = line(at: caret)
        // Which line of the table, skipping the delimiter row.
        var lineNumber = 0
        var probe = source.location
        while probe < line.location {
            probe = NSMaxRange(self.line(at: probe)) + 1
            lineNumber += 1
        }
        let row = lineNumber == 0 ? 0 : max(0, lineNumber - 1)
        let lineText = string(line)
        let ranges = MarkdownTable.cellRanges(in: lineText)
        guard !ranges.isEmpty else { return nil }
        let column = ranges.lastIndex { $0.lowerBound <= caret - line.location } ?? 0
        let units = Array(lineText.utf16)
        let cell = ranges[column]
        var leading = units[cell].prefix { $0 == 32 }.count
        if leading == cell.count { leading = min(1, cell.count) }
        let offset = lineNumber == 1 ? 0 : max(0, caret - line.location - cell.lowerBound - leading)
        return TableCell(block: block, row: row, column: column, offset: offset)
    }

    /// The table holding the caret, parsed.
    public func table(_ cell: TableCell) -> MarkdownTable? {
        MarkdownTable(parsing: index.blocks[cell.block].source)
    }

    /// Re-pads the caret's table so its columns line up, keeping the caret in its cell.
    public func formatTable() -> TextEdit? {
        guard let cell = tableCell, let table = table(cell) else { return nil }
        return tableEdit(cell, table: table, caret: cell)
    }

    /// Re-pads table `block` wherever the caret is, moving the caret along when the table
    /// above it changes length. Nil when it's already tidy or doesn't parse.
    public func formatTable(block: Int) -> TextEdit? {
        guard index.blocks.indices.contains(block), index.blocks[block].kind == .table,
            let table = MarkdownTable(parsing: index.blocks[block].source)
        else { return nil }
        let source = index.sourceRange(of: block)
        let markdown = table.markdown
        guard markdown != index.blocks[block].source else { return nil }
        let delta = markdown.utf16.count - source.count
        func moved(_ offset: Int) -> Int {
            offset >= source.upperBound ? offset + delta : min(offset, source.lowerBound + markdown.utf16.count)
        }
        let edit = TextEdit.difference(from: index.blocks[block].source, to: markdown, selection: 0..<0)
        return TextEdit(
            range: (edit.range.lowerBound + source.lowerBound)..<(edit.range.upperBound + source.lowerBound),
            replacement: edit.replacement, selection: moved(selection.lowerBound)..<moved(selection.upperBound))
    }

    /// Tab and Shift-Tab: the next or previous cell, row by row. Tab in the last cell adds
    /// a row.
    public func moveToNextCell(backward: Bool) -> TextEdit? {
        guard let cell = tableCell, var table = table(cell) else { return nil }
        var target = cell
        target.offset = .max
        if backward {
            if cell.column > 0 {
                target.column -= 1
            } else if cell.row > 0 {
                target.row -= 1
                target.column = table.columnCount - 1
            }
        } else if cell.column < table.columnCount - 1 {
            target.column += 1
        } else {
            if cell.row == table.rowCount - 1 { table.insertRow(at: table.rowCount) }
            target.row += 1
            target.column = 0
        }
        return tableEdit(cell, table: table, caret: target)
    }

    /// Enter: the cell below, or a new row when the caret is in the last one.
    public func tableNewline() -> TextEdit? {
        guard let cell = tableCell, var table = table(cell) else { return nil }
        if cell.row == table.rowCount - 1 { table.insertRow(at: table.rowCount) }
        return tableEdit(
            cell, table: table,
            caret: TableCell(block: cell.block, row: cell.row + 1, column: cell.column, offset: .max))
    }

    public enum TableChange: Sendable {
        case insertRowAbove, insertRowBelow, deleteRow
        case insertColumnLeft, insertColumnRight, deleteColumn
        case align(MarkdownTable.Alignment)
    }

    /// Adds or removes the caret's row or column, or sets its column's alignment.
    public func changeTable(_ change: TableChange) -> TextEdit? {
        guard let cell = tableCell, var table = table(cell) else { return nil }
        var caret = cell
        switch change {
        case .insertRowAbove:
            table.insertRow(at: max(1, cell.row))
            caret.row = max(1, cell.row)
            caret.offset = 0
        case .insertRowBelow:
            table.insertRow(at: cell.row + 1)
            caret.row = cell.row + 1
            caret.offset = 0
        case .deleteRow:
            guard cell.row > 0 else { return nil }
            table.removeRow(at: cell.row)
            caret.row = min(cell.row, table.rowCount - 1)
        case .insertColumnLeft:
            table.insertColumn(at: cell.column)
            caret.offset = 0
        case .insertColumnRight:
            table.insertColumn(at: cell.column + 1)
            caret.column += 1
            caret.offset = 0
        case .deleteColumn:
            guard table.columnCount > 1 else { return nil }
            table.removeColumn(at: cell.column)
            caret.column = min(cell.column, table.columnCount - 1)
        case .align(let alignment):
            table.alignments[cell.column] = alignment
        }
        return tableEdit(cell, table: table, caret: caret)
    }

    /// Replaces the table's source with `table`, formatted, with the caret in `caret`'s cell.
    private func tableEdit(_ cell: TableCell, table: MarkdownTable, caret: TableCell) -> TextEdit {
        let source = index.sourceRange(of: cell.block)
        let markdown = table.markdown
        let offset = source.lowerBound + Self.offset(of: caret, in: markdown, table: table)
        let edit = TextEdit.difference(
            from: string(NSRange(source)), to: markdown, selection: offset..<offset)
        return TextEdit(
            range: (edit.range.lowerBound + source.lowerBound)..<(edit.range.upperBound + source.lowerBound),
            replacement: edit.replacement, selection: offset..<offset)
    }

    /// Where `cell` lands in a formatted table's markdown, clamped to the cell's text.
    static func offset(of cell: TableCell, in markdown: String, table: MarkdownTable) -> Int {
        let lines = markdown.components(separatedBy: "\n")
        let row = min(max(cell.row, 0), table.rowCount - 1)
        let lineNumber = row == 0 ? 0 : row + 1
        let lineStart = lines.prefix(lineNumber).reduce(0) { $0 + $1.utf16.count + 1 }
        let line = lines[lineNumber]
        let ranges = MarkdownTable.cellRanges(in: line)
        let range = ranges[min(max(cell.column, 0), ranges.count - 1)]
        let units = Array(line.utf16)[range]
        var leading = units.prefix { $0 == 32 }.count
        // An empty cell: sit just inside it, after the space by the pipe.
        if leading == range.count { leading = min(1, range.count) }
        let trailing = units.reversed().prefix { $0 == 32 }.count
        let length = max(0, range.count - leading - trailing)
        return lineStart + range.lowerBound + leading + min(cell.offset, length)
    }
}

extension NSRange {
    fileprivate init(_ range: Range<Int>) {
        self.init(location: range.lowerBound, length: range.count)
    }
}
