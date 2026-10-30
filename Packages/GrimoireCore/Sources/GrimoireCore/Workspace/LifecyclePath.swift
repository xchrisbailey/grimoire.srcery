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
        // A reservation keeps its recorded spelling even when an unrelated alias appears.
        try overlaps(
            components(root) + reference.relativePath.split(separator: "/").map(String.init),
            components(url), caseSensitiveNames: caseSensitiveNames)
    }

    static func overlaps(_ left: URL, _ right: URL, caseSensitiveNames: (URL) -> Bool?) throws -> Bool {
        try overlaps(components(left), components(right), caseSensitiveNames: caseSensitiveNames)
    }

    /// Unavailable foreign roots still reserve plausible paths, but can never prove recovery.
    static func mayOverlap(
        _ url: URL, reference: FileReference, in root: URL,
        caseSensitiveNames: (URL) -> Bool?
    ) throws -> Bool {
        let rootParts = reservationComponents(root)
        let parts = reservationComponents(url)
        return try overlaps(
            rootParts + reference.relativePath.split(separator: "/").map(String.init),
            parts, caseSensitiveNames: caseSensitiveNames)
    }

    private static func reservationComponents(_ url: URL) -> [String] {
        var ancestor = url
        var suffix: [String] = []
        while ancestor.pathComponents.count > 1 {
            if let parts = try? components(ancestor) { return parts + suffix }
            suffix.insert(ancestor.lastPathComponent, at: 0)
            ancestor.deleteLastPathComponent()
        }
        return ancestor.standardizedFileURL.pathComponents + suffix
    }

    static func overlaps(
        _ left: FileReference, in leftRoot: URL, _ right: FileReference, in rightRoot: URL,
        caseSensitiveNames: (URL) -> Bool?
    ) throws -> Bool {
        try overlaps(
            components(leftRoot) + left.relativePath.split(separator: "/").map(String.init),
            components(rightRoot) + right.relativePath.split(separator: "/").map(String.init),
            caseSensitiveNames: caseSensitiveNames)
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
