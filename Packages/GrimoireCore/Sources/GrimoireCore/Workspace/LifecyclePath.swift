import Darwin
import Foundation

enum LifecyclePath {
    /// Foundation can standardize an existing macOS temporary path to `/var` while
    /// leaving a missing descendant under `/private/var`. Resolve the existing ancestor
    /// once and retain the missing suffix, so stored destination conflicts stay visible.
    static func components(_ url: URL) throws -> [String] {
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
        return ancestor.standardizedFileURL.resolvingSymlinksInPath().pathComponents + suffix
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
        let recorded = owner[parent.count].precomposedStringWithCanonicalMapping
        let proposed = destination.lastPathComponent.precomposedStringWithCanonicalMapping
        if recorded == proposed { return true }
        if caseSensitive == true { return false }
        // POSIX folding is invariant under the user's language/region settings. Only
        // unresolved names below the already-resolved destination parent are compared.
        let locale = Locale(identifier: "en_US_POSIX")
        guard
            recorded.folding(options: .caseInsensitive, locale: locale).precomposedStringWithCanonicalMapping
                == proposed.folding(options: .caseInsensitive, locale: locale).precomposedStringWithCanonicalMapping
        else { return false }
        guard caseSensitive != nil else { throw LifecycleError.unknownNameEquivalence }
        return true
    }
}
