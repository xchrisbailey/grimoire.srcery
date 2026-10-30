import Foundation

/// Reads and writes the list of projects as one JSON file.
public struct ProjectStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `Application Support/<bundle id>/projects.json`. Inside the sandbox the system
    /// already scopes Application Support to the app's container.
    public static func standard(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "computer.srcery.grimoire")
        -> ProjectStore
    {
        let support = URL.applicationSupportDirectory.appending(path: bundleIdentifier, directoryHint: .isDirectory)
        return ProjectStore(fileURL: support.appending(path: "projects.json"))
    }

    private struct Contents: Codable {
        var version = 1
        var projects: [Project]
    }

    /// The saved projects, or none when nothing has been saved yet.
    public func load() throws -> [Project] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        let contents = try JSONDecoder().decode(Contents.self, from: data)
        guard contents.version == 1 else { throw ProjectStoreError.unsupportedVersion(contents.version) }
        return contents.projects
    }

    public func save(_ projects: [Project]) throws {
        for project in projects { try FolderTemplateAssignment.validate(project.templateAssignments) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Contents(projects: projects)).write(to: fileURL, options: .atomic)
    }
}

public enum ProjectStoreError: LocalizedError {
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            String(localized: "This projects file uses an unsupported version (\(version)).")
        }
    }
}
