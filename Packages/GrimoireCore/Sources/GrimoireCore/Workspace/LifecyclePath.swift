import Darwin
import Foundation

enum LifecyclePath {
    /// Foundation can standardize an existing macOS temporary path to `/var` while
    /// leaving a missing descendant under `/private/var`. Resolve the existing ancestor
    /// once and retain the missing suffix, so stored destination conflicts stay visible.
    static func components(_ url: URL) throws -> [String] {
        let path = try resolved(url)
        return path.ancestor.standardizedFileURL.resolvingSymlinksInPath().pathComponents + path.suffix
    }

    private static func resolved(_ url: URL) throws -> (ancestor: URL, suffix: [String]) {
        var ancestor = url
        var suffix: [String] = []
        var info = stat()
        while lstat(ancestor.path(percentEncoded: false), &info) != 0 {
            guard errno == ENOENT, ancestor.pathComponents.count > 1 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            suffix.insert(ancestor.lastPathComponent, at: 0)
            ancestor.deleteLastPathComponent()
        }
        guard FileManager.default.fileExists(atPath: ancestor.path) else {
            throw TemplateAssignmentError.invalidReference
        }
        return (ancestor, suffix)
    }

    static func volumeCaseSensitiveNames(at url: URL) -> Bool? {
        guard let path = try? resolved(url) else { return nil }
        return (try? path.ancestor.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames
    }

    static func reference(rootID: UUID, root: URL, url: URL) throws -> FileReference? {
        let rootParts = try components(root)
        let parts = try components(url)
        guard parts.starts(with: rootParts) else { return nil }
        return FileReference(rootID: rootID, relativePath: parts.dropFirst(rootParts.count).joined(separator: "/"))
    }

    static func destinationContains(_ url: URL, destination: URL, caseSensitive: Bool?) throws -> Bool {
        let parent = try components(destination.deletingLastPathComponent())
        let owner = try components(url)
        guard owner.starts(with: parent), owner.count > parent.count else { return false }
        return try namesEqual(owner[parent.count], destination.lastPathComponent, caseSensitive: caseSensitive)
    }

    static func namesEqual(_ left: String, _ right: String, caseSensitive: Bool?) throws -> Bool {
        let recorded = left.precomposedStringWithCanonicalMapping
        let proposed = right.precomposedStringWithCanonicalMapping
        if recorded == proposed { return true }
        if caseSensitive == true { return false }
        // POSIX folding is invariant under the user's language/region settings.
        let locale = Locale(identifier: "en_US_POSIX")
        guard
            recorded.folding(options: .caseInsensitive, locale: locale).precomposedStringWithCanonicalMapping
                == proposed.folding(options: .caseInsensitive, locale: locale).precomposedStringWithCanonicalMapping
        else { return false }
        guard caseSensitive != nil else { throw LifecycleError.unknownNameEquivalence }
        return true
    }

    static func overlaps(
        _ url: URL, reference: FileReference, in root: URL,
        caseSensitiveNames: (URL) -> Bool?
    ) throws -> Bool {
        try overlaps(
            reservationPaths(url), reservationPaths(reference, in: root),
            caseSensitiveNames: caseSensitiveNames)
    }

    static func overlaps(_ left: URL, _ right: URL, caseSensitiveNames: (URL) -> Bool?) throws -> Bool {
        try overlaps(reservationPaths(left), reservationPaths(right), caseSensitiveNames: caseSensitiveNames)
    }

    /// Lexical paths, live aliases and observed identity can deny a conflict, never prove completion.
    static func reserves(
        _ url: URL, operation: PendingLifecycleOperation, roots: [UUID: URL],
        caseSensitiveNames: (URL) -> Bool?
    ) throws -> Bool {
        for path in [url, url.resolvingSymlinksInPath()] {
            var ancestor = path
            while ancestor.pathComponents.count > 1 {
                if (try? LifecycleIdentity(ancestor)) == operation.itemIdentity { return true }
                ancestor.deleteLastPathComponent()
            }
        }
        return try operation.reservedReferences.contains {
            guard let root = roots[$0.rootID] else { throw LifecycleError.pendingRepair }
            return try overlaps(url, reference: $0, in: root, caseSensitiveNames: caseSensitiveNames)
        }
    }

    private static func reservationPaths(_ url: URL) -> [[String]] {
        [url.standardizedFileURL.pathComponents, reservationComponents(url)]
    }

    private static func reservationPaths(_ reference: FileReference, in root: URL) -> [[String]] {
        let relative = reference.relativePath.split(separator: "/").map(String.init)
        // Retain the recorded suffix even when resolving a newly substituted parent changes its path.
        return reservationPaths(root).map { $0 + relative } + reservationPaths(reference.url(in: root))
    }

    private static func reservationComponents(_ url: URL) -> [String] {
        var remaining = Array(url.standardizedFileURL.pathComponents.dropFirst())
        var parts = ["/"]
        var links = 0
        while !remaining.isEmpty {
            let name = remaining.removeFirst()
            if name == "." { continue }
            if name == ".." {
                if parts.count > 1 { parts.removeLast() }
                continue
            }
            let candidate = URL(filePath: "/" + (Array(parts.dropFirst()) + [name]).joined(separator: "/"))
            if links < 40, let target = symlinkTarget(candidate) {
                remaining = Array(target.pathComponents.dropFirst()) + remaining
                parts = ["/"]
                links += 1
            } else {
                parts.append(name)
            }
        }
        return parts
    }

    private static func symlinkTarget(_ url: URL) -> URL? {
        var info = stat()
        let path = LifecycleIdentity.entryPath(url)
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFLNK,
            let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path)
        else { return nil }
        // Resolve links without canonicalizing ordinary entry spelling; volume-aware comparison
        // still decides whether case/Unicode variants are equivalent, including missing leaves.
        return URL(filePath: target, relativeTo: url.deletingLastPathComponent()).absoluteURL
    }

    static func overlaps(
        _ left: FileReference, in leftRoot: URL, _ right: FileReference, in rightRoot: URL,
        caseSensitiveNames: (URL) -> Bool?
    ) throws -> Bool {
        try overlaps(
            reservationPaths(left, in: leftRoot), reservationPaths(right, in: rightRoot),
            caseSensitiveNames: caseSensitiveNames)
    }

    static func contains(
        _ ancestor: FileReference, in ancestorRoot: URL, _ descendant: FileReference, in descendantRoot: URL,
        caseSensitiveNames: (URL) -> Bool?
    ) throws -> Bool {
        try reservationPaths(ancestor, in: ancestorRoot).contains { parent in
            try reservationPaths(descendant, in: descendantRoot).contains { child in
                guard child.count >= parent.count else { return false }
                return try overlaps(parent, child, caseSensitiveNames: caseSensitiveNames)
            }
        }
    }

    private static func overlaps(_ left: [[String]], _ right: [[String]], caseSensitiveNames: (URL) -> Bool?) throws
        -> Bool
    {
        try left.contains { lhs in
            try right.contains { rhs in try overlaps(lhs, rhs, caseSensitiveNames: caseSensitiveNames) }
        }
    }

    private static func overlaps(_ left: [String], _ right: [String], caseSensitiveNames: (URL) -> Bool?) throws -> Bool
    {
        for index in 0..<min(left.count, right.count) where left[index] != right[index] {
            let parent = URL(filePath: "/" + left.prefix(index).dropFirst().joined(separator: "/"))
            guard try namesEqual(left[index], right[index], caseSensitive: caseSensitiveNames(parent)) else {
                return false
            }
        }
        return true
    }
}
