/// A line-by-line comparison of two texts, for showing what a version changes.
public struct LineDiff: Equatable, Sendable {
    public var lines: [DiffLine]

    public var added: Int { lines.count { $0.kind == .added } }
    public var removed: Int { lines.count { $0.kind == .removed } }
    public var isEmpty: Bool { added == 0 && removed == 0 }

    /// The changes from `old` to `new`, keeping `context` unchanged lines around each change.
    public init(from old: String, to new: String, context: Int = 3) {
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let difference = newLines.difference(from: oldLines)
        var removedAt = Set<Int>()
        var insertedAt = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removedAt.insert(offset)
            case .insert(let offset, _, _): insertedAt.insert(offset)
            }
        }
        // Walk both sides together: removals come from the old text, insertions from the new.
        var full: [DiffLine] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < oldLines.count || newIndex < newLines.count {
            if oldIndex < oldLines.count, removedAt.contains(oldIndex) {
                full.append(DiffLine(kind: .removed, text: oldLines[oldIndex]))
                oldIndex += 1
            } else if newIndex < newLines.count, insertedAt.contains(newIndex) {
                full.append(DiffLine(kind: .added, text: newLines[newIndex]))
                newIndex += 1
            } else {
                if newIndex < newLines.count { full.append(DiffLine(kind: .same, text: newLines[newIndex])) }
                oldIndex += 1
                newIndex += 1
            }
        }
        lines = Self.collapse(full, context: context)
    }

    /// Replaces long unchanged stretches with a `.skipped` marker.
    private static func collapse(_ lines: [DiffLine], context: Int) -> [DiffLine] {
        let changed = lines.indices.filter { lines[$0].kind != .same }
        guard !changed.isEmpty else { return lines.isEmpty ? [] : [DiffLine(kind: .skipped(lines.count), text: "")] }
        var keep = Set<Int>()
        for index in changed {
            for near in max(0, index - context)...min(lines.count - 1, index + context) { keep.insert(near) }
        }
        var result: [DiffLine] = []
        var skipped = 0
        for index in lines.indices {
            if keep.contains(index) {
                if skipped > 0 { result.append(DiffLine(kind: .skipped(skipped), text: "")) }
                skipped = 0
                result.append(lines[index])
            } else {
                skipped += 1
            }
        }
        if skipped > 0 { result.append(DiffLine(kind: .skipped(skipped), text: "")) }
        return result
    }
}

/// One line of a diff.
public struct DiffLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case same, added, removed
        /// Unchanged lines left out between changes.
        case skipped(Int)
    }

    public var kind: Kind
    public var text: String
}
