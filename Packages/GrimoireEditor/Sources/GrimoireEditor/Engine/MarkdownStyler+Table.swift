import CoreGraphics
import Foundation
import GrimoireCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Tables in Preview: a grid. The pipes and padding stay in the text but take no room; each
/// pipe gets kerning that pushes the next cell to its column's edge, so columns line up
/// live as cells are typed in, whatever font the text uses.
extension MarkdownStyler {
    /// Space between a cell's text and its column edge.
    static let cellPadding: CGFloat = 10
    static let minimumColumnWidth: CGFloat = 36

    func styleTable(_ range: NSRange, in storage: NSMutableAttributedString, reveal: Bool) {
        let text = storage.string as NSString
        var lines: [NSRange] = []
        forEachLine(of: range, in: text) { lines.append($0) }
        guard lines.count >= 2, MarkdownTable(parsing: text.substring(with: range)) != nil else {
            return styleSource(range, in: storage)
        }
        let rows = lines.enumerated().filter { $0.offset != 1 }.map(\.element)
        let header = theme.font(weight: 650)
        let cells = rows.map { line in
            MarkdownTable.cellRanges(in: text.substring(with: line)).map {
                NSRange(location: line.location + $0.lowerBound, length: $0.count)
            }
        }
        let columns = cells.map(\.count).max() ?? 0

        applyRowMetrics(range, in: storage)

        // Style cell text first, so widths are measured with the fonts it will draw in.
        // Markers show only on the caret's row.
        for (row, rowCells) in cells.enumerated() {
            let showsMarkers =
                reveal && caret.map { NSLocationInRange($0, rows[row]) || $0 == NSMaxRange(rows[row]) } == true
            for cell in rowCells {
                let content = trimmed(cell, in: text)
                if row == 0 { storage.addAttribute(.font, value: header, range: content) }
                styleInline(content, in: storage, baseFont: row == 0 ? header : theme.body, reveal: showsMarkers)
            }
        }
        // Each cell's text width, measured once.
        let measured = cells.enumerated().map { row, rowCells in
            rowCells.map { cellWidth(storage.attributedSubstring(from: trimmed($0, in: text)), isHeader: row == 0) }
        }
        var widths = Array(repeating: Self.minimumColumnWidth, count: columns)
        for rowWidths in measured {
            for (column, width) in rowWidths.enumerated() { widths[column] = max(widths[column], width) }
        }
        var edges: [CGFloat] = [0]
        for width in widths { edges.append((edges.last ?? 0) + width + Self.cellPadding * 2) }

        for (row, line) in rows.enumerated() {
            hideSyntax(line, cells: cells[row], measured: measured[row], widths: widths, in: storage)
            storage.addAttribute(
                .grimoireDecoration,
                value: LineDecoration(.tableRow(edges: edges, isHeader: row == 0, isLast: row == rows.count - 1)),
                range: line)
        }
        // The delimiter row folds away; the header's bottom edge stands in for it.
        let delimiter = lines[1]
        storage.addAttributes(
            [
                .font: EditorTheme.hiddenFont, .foregroundColor: PlatformColor.clear, .grimoireMarker: true,
                .paragraphStyle: paragraphStyle(lineHeight: 0.01), .grimoireDecoration: LineDecoration(.tableDelimiter),
            ],
            range: delimiter)
    }

    /// Rows are a fixed height with the text centered in them, even when a row is empty.
    private func applyRowMetrics(_ range: NSRange, in storage: NSMutableAttributedString) {
        let rowHeight = (theme.bodySize * 2.2).rounded()
        let rowStyle = NSMutableParagraphStyle()
        rowStyle.minimumLineHeight = rowHeight
        rowStyle.maximumLineHeight = rowHeight
        let natural = theme.body.ascender - theme.body.descender
        // The last row's line break sits outside the block's source; it needs the same line
        // metrics or that row comes out taller.
        var rowsRange = range
        if NSMaxRange(range) < storage.length { rowsRange.length += 1 }
        storage.addAttributes(
            [.paragraphStyle: rowStyle, .baselineOffset: ((rowHeight - natural) / 2).rounded()], range: rowsRange)
    }

    /// Hides a row's pipes and padding and kerns each pipe out to its column's edge.
    private func hideSyntax(
        _ line: NSRange, cells: [NSRange], measured: [CGFloat], widths: [CGFloat], in storage: NSMutableAttributedString
    ) {
        let text = storage.string as NSString
        let hidden: [NSAttributedString.Key: Any] = [
            .font: EditorTheme.hiddenFont, .foregroundColor: PlatformColor.clear, .grimoireMarker: true,
        ]
        var cursor = line.location
        for (column, cell) in cells.enumerated() {
            let content = trimmed(cell, in: text)
            // Everything from the last cell's text to this one's: pipe and padding.
            let gap = NSRange(location: cursor, length: max(0, content.location - cursor))
            storage.addAttributes(hidden, range: gap)
            let previousFill: CGFloat = column == 0 ? 0 : widths[column - 1] - measured[column - 1]
            if gap.length > 0 {
                let pipe = NSRange(location: gap.location, length: 1)
                storage.addAttribute(.kern, value: previousFill + Self.cellPadding * (column == 0 ? 1 : 2), range: pipe)
            }
            cursor = NSMaxRange(content)
        }
        // The trailing padding and pipe close the last column.
        let tail = NSRange(location: cursor, length: max(0, NSMaxRange(line) - cursor))
        storage.addAttributes(hidden, range: tail)
        if !cells.isEmpty, tail.length > 0 {
            let fill = widths[cells.count - 1] - measured[cells.count - 1]
            storage.addAttribute(
                .kern, value: fill + Self.cellPadding, range: NSRange(location: tail.location, length: 1))
        }
    }

    /// A cell's drawn width. Most cells don't change between keystrokes, so widths are
    /// remembered by their text and styling.
    private func cellWidth(_ cell: NSAttributedString, isHeader: Bool) -> CGFloat {
        var hasher = Hasher()
        hasher.combine(cell.string)
        hasher.combine(isHeader)
        cell.enumerateAttribute(.font, in: NSRange(location: 0, length: cell.length)) { font, range, _ in
            hasher.combine((font as? PlatformFont)?.pointSize)
            hasher.combine((font as? PlatformFont)?.fontName)
            hasher.combine(range.location)
        }
        let key = hasher.finalize()
        if let width = cellWidths[key] { return width }
        let width = cell.size().width
        if cellWidths.count > 4_000 { cellWidths.removeAll() }
        cellWidths[key] = width
        return width
    }

    /// A cell's range without the spaces around its text. An empty cell keeps a zero-length
    /// range just inside its pipe.
    private func trimmed(_ cell: NSRange, in text: NSString) -> NSRange {
        let string = text.substring(with: cell)
        let units = Array(string.utf16)
        let leading = units.prefix { $0 == 32 || $0 == 9 }.count
        guard leading < units.count else { return NSRange(location: cell.location + min(1, cell.length), length: 0) }
        let trailing = units.reversed().prefix { $0 == 32 || $0 == 9 }.count
        return NSRange(location: cell.location + leading, length: units.count - leading - trailing)
    }

    /// A table that doesn't parse as a grid shows as mono source with dim pipes.
    private func styleSource(_ range: NSRange, in storage: NSMutableAttributedString) {
        let font = theme.font(size: theme.codeSize, monospaced: true)
        storage.addAttributes([.font: font, .paragraphStyle: paragraphStyle(lineHeight: 1.15)], range: range)
        let text = storage.string as NSString
        for offset in 0..<range.length where text.character(at: range.location + offset) == UInt16(UInt8(ascii: "|")) {
            storage.addAttribute(
                .foregroundColor, value: theme.marker, range: NSRange(location: range.location + offset, length: 1))
        }
    }
}
