import Foundation

/// A GFM pipe table as rows of cells, for editing tables as a grid while the file keeps
/// plain pipe syntax.
///
/// Cells hold their markdown as written (inline syntax and `\|` escapes intact), trimmed of
/// the padding around them. `markdown` writes the table back padded so its columns line up.
public struct MarkdownTable: Equatable, Sendable {
    public enum Alignment: Equatable, Sendable {
        case none, left, center, right
    }

    /// The header row first, then the body rows. Every row has `columnCount` cells.
    public var rows: [[String]]
    public var alignments: [Alignment]

    public var columnCount: Int { alignments.count }
    public var rowCount: Int { rows.count }

    public init(rows: [[String]], alignments: [Alignment]? = nil) {
        let columns = max(alignments?.count ?? 0, rows.map(\.count).max() ?? 0, 1)
        self.rows = rows.map { Self.padded($0, to: columns) }
        if self.rows.isEmpty { self.rows = [Array(repeating: "", count: columns)] }
        self.alignments = Self.padded(alignments ?? [], to: columns, with: .none)
    }

    /// An empty table with a header row and `bodyRows` rows.
    public static func empty(columns: Int, bodyRows: Int) -> MarkdownTable {
        let header = (1...max(columns, 1)).map { "Column \($0)" }
        let body = Array(repeating: Array(repeating: "", count: columns), count: bodyRows)
        return MarkdownTable(rows: [header] + body)
    }

    // MARK: - Parsing

    /// Reads a table's source. Returns nil when the second line isn't a delimiter row.
    public init?(parsing source: String) {
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard lines.count >= 2, let alignments = Self.delimiterAlignments(lines[1]) else { return nil }
        let rows = [lines[0]] + lines.dropFirst(2).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        self.init(rows: rows.map(Self.cells), alignments: alignments)
    }

    /// The cells of one row, trimmed, with `\|` kept as written.
    static func cells(_ line: String) -> [String] {
        let units = Array(line.utf16)
        return cellRanges(in: line).map {
            String(decoding: units[$0], as: UTF16.self).trimmingCharacters(in: .whitespaces)
        }
    }

    /// UTF-16 ranges of each cell's text in `line`, between its pipes, padding included.
    /// Pipes escaped with `\` or inside code spans don't split cells.
    public static func cellRanges(in line: String) -> [Range<Int>] {
        let units = Array(line.utf16)
        var pipes: [Int] = []
        var escaped = false
        var inCode = false
        for (offset, unit) in units.enumerated() {
            if escaped {
                escaped = false
            } else if unit == backslash {
                escaped = true
            } else if unit == backtick {
                inCode.toggle()
            } else if unit == pipe, !inCode {
                pipes.append(offset)
            }
        }
        var segments: [Range<Int>] = []
        var start = 0
        for pipe in pipes {
            segments.append(start..<pipe)
            start = pipe + 1
        }
        segments.append(start..<units.count)
        func isBlank(_ range: Range<Int>) -> Bool { units[range].allSatisfy { $0 == 32 || $0 == 9 } }
        // The leading and trailing pipes are optional; when present they leave blank ends.
        if !pipes.isEmpty, let first = segments.first, isBlank(first) { segments.removeFirst() }
        if !pipes.isEmpty, let last = segments.last, isBlank(last), segments.count > 1 { segments.removeLast() }
        return segments
    }

    static func delimiterAlignments(_ line: String) -> [Alignment]? {
        let cells = Self.cells(line)
        guard !cells.isEmpty else { return nil }
        var alignments: [Alignment] = []
        for cell in cells {
            let dashes = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
            case (true, true): alignments.append(.center)
            case (true, false): alignments.append(.left)
            case (false, true): alignments.append(.right)
            case (false, false): alignments.append(.none)
            }
        }
        return alignments
    }

    // MARK: - Writing

    /// The table as aligned pipe syntax, without a trailing line break.
    public var markdown: String {
        let widths = (0..<columnCount).map { column in
            max(3, rows.map { Self.displayWidth($0[column]) }.max() ?? 0)
        }
        var lines: [String] = []
        for (number, row) in rows.enumerated() {
            lines.append(line(row, widths: widths))
            if number == 0 { lines.append(delimiterLine(widths: widths)) }
        }
        return lines.joined(separator: "\n")
    }

    private func line(_ cells: [String], widths: [Int]) -> String {
        let padded = cells.enumerated().map { column, cell in
            Self.pad(cell, to: widths[column], alignment: alignments[column])
        }
        return "| " + padded.joined(separator: " | ") + " |"
    }

    private func delimiterLine(widths: [Int]) -> String {
        let cells = alignments.enumerated().map { column, alignment -> String in
            let width = widths[column]
            switch alignment {
            case .none: return String(repeating: "-", count: width)
            case .left: return ":" + String(repeating: "-", count: width - 1)
            case .right: return String(repeating: "-", count: width - 1) + ":"
            case .center: return ":" + String(repeating: "-", count: width - 2) + ":"
            }
        }
        return "| " + cells.joined(separator: " | ") + " |"
    }

    static func pad(_ cell: String, to width: Int, alignment: Alignment) -> String {
        let space = max(0, width - displayWidth(cell))
        switch alignment {
        case .right: return String(repeating: " ", count: space) + cell
        case .center:
            let left = space / 2
            return String(repeating: " ", count: left) + cell + String(repeating: " ", count: space - left)
        case .none, .left: return cell + String(repeating: " ", count: space)
        }
    }

    /// Columns a string takes in a monospaced font: wide East Asian characters and emoji
    /// count as two.
    public static func displayWidth(_ string: String) -> Int {
        string.reduce(0) { width, character in
            let scalar = character.unicodeScalars.first?.value ?? 0
            let isWide =
                character.unicodeScalars.first?.properties.isEmojiPresentation == true
                || (0x1100...0x115F).contains(scalar) || (0x2E80...0xA4CF).contains(scalar)
                || (0xAC00...0xD7A3).contains(scalar) || (0xF900...0xFAFF).contains(scalar)
                || (0xFE30...0xFE4F).contains(scalar) || (0xFF00...0xFF60).contains(scalar)
                || (0xFFE0...0xFFE6).contains(scalar)
            return width + (isWide ? 2 : 1)
        }
    }

    // MARK: - Editing

    public mutating func insertRow(at index: Int) {
        rows.insert(Array(repeating: "", count: columnCount), at: min(max(index, 1), rows.count))
    }

    /// Removes a body row. The header row stays.
    public mutating func removeRow(at index: Int) {
        guard index > 0, rows.indices.contains(index) else { return }
        rows.remove(at: index)
    }

    public mutating func insertColumn(at index: Int) {
        let index = min(max(index, 0), columnCount)
        for row in rows.indices { rows[row].insert("", at: index) }
        alignments.insert(.none, at: index)
    }

    /// Removes a column, unless it's the last one.
    public mutating func removeColumn(at index: Int) {
        guard columnCount > 1, alignments.indices.contains(index) else { return }
        for row in rows.indices { rows[row].remove(at: index) }
        alignments.remove(at: index)
    }

    // MARK: - Pasting

    /// A table from tab-separated text (Numbers, Excel and Sheets copy this), or from CSV
    /// when `csv` is set. The first row becomes the header. Nil unless there are at least two
    /// rows and two columns.
    public init?(delimited text: String, csv: Bool = false) {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        let rows = lines.map { csv ? Self.csvFields($0) : $0.components(separatedBy: "\t") }
        guard rows.count >= 2, let width = rows.map(\.count).max(), width >= 2 else { return nil }
        self.init(rows: rows.map { $0.map(Self.escapeCell) }, alignments: Array(repeating: .none, count: width))
    }

    private static func csvFields(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var quoted = false
        var iterator = Array(line).makeIterator()
        var pending: Character? = iterator.next()
        while let character = pending {
            pending = iterator.next()
            if quoted {
                if character == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = iterator.next()
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                quoted = true
            } else if character == "," {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
        }
        fields.append(field)
        return fields
    }

    /// Makes text safe inside a cell: pipes escaped, line breaks flattened.
    static func escapeCell(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func padded<T>(_ values: [T], to count: Int, with filler: T) -> [T] {
        values.count >= count
            ? Array(values.prefix(count)) : values + Array(repeating: filler, count: count - values.count)
    }

    private static func padded(_ cells: [String], to count: Int) -> [String] {
        padded(cells, to: count, with: "")
    }

    private static let pipe = UInt16(UInt8(ascii: "|"))
    private static let backslash = UInt16(UInt8(ascii: "\\"))
    private static let backtick = UInt16(UInt8(ascii: "`"))
}
