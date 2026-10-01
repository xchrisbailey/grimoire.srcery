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
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Contents.self, from: data).projects
    }

    public func save(_ projects: [Project]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Contents(projects: projects)).write(to: fileURL, options: .atomic)
    }
}
