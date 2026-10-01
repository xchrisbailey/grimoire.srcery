import Foundation

/// The file operations the project tree offers. Each one returns where the item ended up.
public enum FileOperations {
    /// Creates an empty document in `folder`, named `Untitled.md`, `Untitled 2.md` and so on.
    @discardableResult
    public static func createDocument(in folder: URL, named baseName: String = "Untitled", extension ext: String = "md")
        throws -> URL
    {
        let url = uniqueURL(in: folder, baseName: baseName, extension: ext)
        guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: Data()) else {
            throw FileOperationError.couldNotCreate(url.lastPathComponent)
        }
        return url
    }

    @discardableResult
    public static func createFolder(in folder: URL, named baseName: String = "New Folder") throws -> URL {
        let url = uniqueURL(in: folder, baseName: baseName, extension: "")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    /// Renames the item at `url`. A document renamed without an extension keeps its old one,
    /// so `potions` becomes `potions.md`.
    @discardableResult
    public static func rename(_ url: URL, to newName: String) throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.hasPrefix(".") else {
            throw FileOperationError.invalidName(newName)
        }
        var name = trimmed
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        if !isFolder, !url.pathExtension.isEmpty, (name as NSString).pathExtension.isEmpty {
            name += "." + url.pathExtension
        }
        let destination = url.deletingLastPathComponent().appending(path: name)
        if destination.lastPathComponent == url.lastPathComponent { return url }
        // A case-only rename is allowed on case-insensitive volumes.
        let isCaseChange = destination.lastPathComponent.lowercased() == url.lastPathComponent.lowercased()
        if !isCaseChange, exists(destination) {
            throw FileOperationError.alreadyExists(name)
        }
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    /// Moves the item at `url` into `folder`.
    @discardableResult
    public static func move(_ url: URL, into folder: URL) throws -> URL {
        let source = url.standardizedFileURL
        let target = folder.standardizedFileURL
        if source.deletingLastPathComponent() == target { return url }
        if target.pathComponents.starts(with: source.pathComponents) {
            throw FileOperationError.cannotMoveIntoItself(url.lastPathComponent)
        }
        let destination = folder.appending(path: url.lastPathComponent)
        if exists(destination) {
            throw FileOperationError.alreadyExists(url.lastPathComponent)
        }
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    /// Moves the item at `url` to the Trash. Returns its URL in the Trash, when the system
    /// reports one.
    @discardableResult
    public static func moveToTrash(_ url: URL) throws -> URL? {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        return trashed as URL?
    }

    /// `baseName.ext` in `folder`, or `baseName 2.ext`, `baseName 3.ext`… when taken.
    public static func uniqueURL(in folder: URL, baseName: String, extension ext: String) -> URL {
        func candidate(_ index: Int) -> URL {
            let stem = index == 1 ? baseName : "\(baseName) \(index)"
            return folder.appending(path: ext.isEmpty ? stem : "\(stem).\(ext)")
        }
        var index = 1
        while exists(candidate(index)) { index += 1 }
        return candidate(index)
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}

/// Why a file operation failed. Errors stay plain, per the brand voice.
public enum FileOperationError: LocalizedError, Equatable {
    case invalidName(String)
    case alreadyExists(String)
    case cannotMoveIntoItself(String)
    case couldNotCreate(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            String(localized: "“\(name)” can't be used as a name.")
        case .alreadyExists(let name):
            String(localized: "An item named “\(name)” already exists here.")
        case .cannotMoveIntoItself(let name):
            String(localized: "Can't move “\(name)” into itself.")
        case .couldNotCreate(let name):
            String(localized: "Couldn't create “\(name)”.")
        }
    }
}
