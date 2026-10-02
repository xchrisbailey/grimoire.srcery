import Foundation

/// One entry in a project's file tree: a folder or a document.
public struct FileNode: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case folder
        case document
    }

    public var url: URL
    public var name: String
    public var kind: Kind
    /// Folder contents, folders first. Always nil for documents, so the node drops
    /// straight into `OutlineGroup(children: \.children)`.
    public var children: [FileNode]?

    public var id: URL { url }
    public var isFolder: Bool { kind == .folder }

    public init(url: URL, name: String? = nil, kind: Kind, children: [FileNode]? = nil) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.kind = kind
        self.children = kind == .folder ? (children ?? []) : nil
    }

    /// Every document at or under this node, depth first.
    public var documents: [FileNode] {
        switch kind {
        case .document: [self]
        case .folder: (children ?? []).flatMap(\.documents)
        }
    }

    /// The node at `url`, searching this node and its descendants.
    public func node(at url: URL) -> FileNode? {
        if self.url.standardizedFileURL == url.standardizedFileURL { return self }
        for child in children ?? [] {
            if let found = child.node(at: url) { return found }
        }
        return nil
    }
}

/// How the sidebar orders a folder's contents.
public enum FileSort: String, Codable, CaseIterable, Sendable {
    /// A to Z, as Finder sorts names.
    case name
    /// Most recently modified first.
    case modified
    /// Most recently created first.
    case created
}

/// Which files the sidebar lists and in what order.
public struct FileListing: Hashable, Sendable {
    public var sort: FileSort
    public var foldersFirst: Bool
    /// Whether files and folders whose names start with a dot are listed.
    public var showsHiddenFiles: Bool

    public init(sort: FileSort = .name, foldersFirst: Bool = true, showsHiddenFiles: Bool = false) {
        self.sort = sort
        self.foldersFirst = foldersFirst
        self.showsHiddenFiles = showsHiddenFiles
    }
}

/// Lists the documents under a folder.
public struct FileScanner: Sendable {
    public var extensions: Set<String>
    /// Folder names never descended into, hidden files shown or not.
    public var skippedFolderNames: Set<String>
    public var listing: FileListing

    public init(
        extensions: Set<String> = GrimoireCore.documentExtensions,
        skippedFolderNames: Set<String> = ["node_modules", ".git", "DerivedData", ".build"],
        listing: FileListing = FileListing()
    ) {
        self.extensions = extensions
        self.skippedFolderNames = skippedFolderNames
        self.listing = listing
    }

    public func isDocument(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    /// The tree under `root`: the root's own node, with its documents and the folders that
    /// lead to them.
    ///
    /// A folder with no documents anywhere under it is left out, so code checkouts don't
    /// flood the tree. Empty folders stay, so a folder made from the tree shows up before
    /// it has anything in it.
    public func scan(_ root: URL) -> FileNode {
        FileNode(url: root, kind: .folder, children: scanChildren(of: root) ?? [])
    }

    /// Children of `folder`, or nil when the folder should be pruned.
    private func scanChildren(of folder: URL) -> [FileNode]? {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .contentModificationDateKey, .creationDateKey,
        ]
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys,
                options: listing.showsHiddenFiles ? [] : [.skipsHiddenFiles])
        else { return nil }
        if entries.isEmpty { return [] }

        var folders: [FileNode] = []
        var documents: [FileNode] = []
        var dates: [URL: Date] = [:]
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: Set(keys))
            switch listing.sort {
            case .name: break
            case .modified: dates[entry] = values?.contentModificationDate
            case .created: dates[entry] = values?.creationDate
            }
            if values?.isDirectory == true {
                // Symlinked folders aren't followed, so a link back up the tree can't loop.
                guard values?.isSymbolicLink != true, !skippedFolderNames.contains(entry.lastPathComponent),
                    let children = scanChildren(of: entry)
                else { continue }
                folders.append(FileNode(url: entry, kind: .folder, children: children))
            } else if isDocument(entry) {
                documents.append(FileNode(url: entry, kind: .document))
            }
        }
        let order = { (lhs: FileNode, rhs: FileNode) in Self.order(lhs, rhs, dates: dates) }
        let children =
            listing.foldersFirst
            ? folders.sorted(by: order) + documents.sorted(by: order) : (folders + documents).sorted(by: order)
        return children.isEmpty ? nil : children
    }

    /// Newest first when sorting by date, names breaking ties; A to Z otherwise.
    private static func order(_ lhs: FileNode, _ rhs: FileNode, dates: [URL: Date]) -> Bool {
        if let left = dates[lhs.url], let right = dates[rhs.url], left != right { return left > right }
        return finderOrder(lhs, rhs)
    }

    static func finderOrder(_ lhs: FileNode, _ rhs: FileNode) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
