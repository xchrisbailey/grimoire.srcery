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
}
