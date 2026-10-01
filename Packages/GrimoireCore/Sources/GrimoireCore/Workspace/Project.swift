import Foundation

/// A named space that holds one or more folders. Every `.md` / `.mdx` file under
/// those folders belongs to the project.
public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// SF Symbol name shown next to the project.
    public var icon: String
    public var color: ProjectColor
    public var roots: [FolderRoot]
    /// The file to reopen when the project is opened again.
    public var lastOpenedFile: FileReference?
    /// Folders the user has expanded in the tree.
    public var expandedFolders: Set<FileReference>
    /// Settings this project keeps for itself.
    public var overrides: ProjectOverrides
    /// Words the spell checker accepts in this project's files, besides the system
    /// dictionary.
    public var dictionary: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "book.closed",
        color: ProjectColor = .magic,
        roots: [FolderRoot] = [],
        lastOpenedFile: FileReference? = nil,
        expandedFolders: Set<FileReference> = [],
        overrides: ProjectOverrides = ProjectOverrides(),
        dictionary: [String] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.roots = roots
        self.lastOpenedFile = lastOpenedFile
        self.expandedFolders = expandedFolders
        self.overrides = overrides
        self.dictionary = dictionary
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, icon, color, roots, lastOpenedFile, expandedFolders, overrides, dictionary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        color = try container.decode(ProjectColor.self, forKey: .color)
        roots = try container.decode([FolderRoot].self, forKey: .roots)
        lastOpenedFile = try container.decodeIfPresent(FileReference.self, forKey: .lastOpenedFile)
        expandedFolders = try container.decode(Set<FileReference>.self, forKey: .expandedFolders)
        // Projects saved before overrides existed have none.
        overrides = try container.decodeIfPresent(ProjectOverrides.self, forKey: .overrides) ?? ProjectOverrides()
        dictionary = try container.decodeIfPresent([String].self, forKey: .dictionary) ?? []
    }

    public func root(_ id: UUID) -> FolderRoot? {
        roots.first { $0.id == id }
    }
}

/// The brand roles a project can be tinted with.
public enum ProjectColor: String, Codable, CaseIterable, Sendable {
    case magic, caret, callout, sparkle, lavender, link, string, quote

    public func color(in palette: BrandPalette) -> PaletteColor {
        switch self {
        case .magic: palette.magic
        case .caret: palette.caret
        case .callout: palette.callout
        case .sparkle: palette.sparkle
        case .lavender: palette.lavender
        case .link: palette.link
        case .string: palette.string
        case .quote: palette.quote
        }
    }
}

/// One folder bound to a project, remembered as a security-scoped bookmark so access
/// survives relaunch under the sandbox.
public struct FolderRoot: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// The folder's name when it was bound or last resolved.
    public var name: String
    public var bookmark: Data
    /// Where the folder was last seen, for the re-grant prompt when the bookmark no
    /// longer resolves.
    public var lastKnownPath: String

    public init(id: UUID = UUID(), name: String, bookmark: Data, lastKnownPath: String) {
        self.id = id
        self.name = name
        self.bookmark = bookmark
        self.lastKnownPath = lastKnownPath
    }

    public var lastKnownURL: URL { URL(filePath: lastKnownPath, directoryHint: .isDirectory) }
}

/// A file or folder inside a project, as a path relative to one of its roots so it
/// stays valid when the root's bookmark resolves somewhere new.
public struct FileReference: Codable, Hashable, Sendable {
    public var rootID: UUID
    /// Slash-separated path from the root, with no leading slash. Empty for the root.
    public var relativePath: String

    public init(rootID: UUID, relativePath: String) {
        self.rootID = rootID
        self.relativePath = relativePath
    }

    /// The reference for `url` inside the root at `rootURL`, or nil when `url` is outside it.
    public init?(rootID: UUID, rootURL: URL, url: URL) {
        let rootComponents = rootURL.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard components.starts(with: rootComponents) else { return nil }
        self.init(rootID: rootID, relativePath: components.dropFirst(rootComponents.count).joined(separator: "/"))
    }

    public func url(in rootURL: URL) -> URL {
        relativePath.isEmpty ? rootURL : rootURL.appending(path: relativePath)
    }
}
