import Foundation

/// Security-scoped bookmarks for bound folders.
///
/// On macOS these are app-scoped security-scoped bookmarks (the app needs the
/// `com.apple.security.files.bookmarks.app-scope` entitlement). iOS bookmarks carry
/// their scope implicitly, so they're created without options.
public enum FolderBookmark {
    #if os(macOS)
    private static let creationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    private static let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    private static let creationOptions: URL.BookmarkCreationOptions = []
    private static let resolutionOptions: URL.BookmarkResolutionOptions = []
    #endif

    /// A bookmark for `url`, which must be a folder the user just picked (or one this
    /// process already has access to).
    public static func make(for url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData(options: creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public struct Resolved: Sendable {
        public var url: URL
        /// The bookmark still resolved, but the system wants it recreated (the folder
        /// moved or was renamed). Recreate it while access is active.
        public var isStale: Bool
    }

    public static func resolve(_ data: Data) throws -> Resolved {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data, options: resolutionOptions, relativeTo: nil, bookmarkDataIsStale: &isStale)
        return Resolved(url: url, isStale: isStale)
    }
}
