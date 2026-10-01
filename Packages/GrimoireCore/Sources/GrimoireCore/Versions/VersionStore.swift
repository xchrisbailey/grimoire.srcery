import CryptoKit
import Foundation

/// One kept copy of a file's text.
public struct Version: Codable, Identifiable, Hashable, Sendable {
    public enum Reason: String, Codable, Sendable {
        /// The text on disk before the first save after a pause.
        case edit
        /// Before Replace All rewrote the file.
        case replaceAll
        /// The text on disk before another app's change was loaded.
        case externalChange
        /// The editor's text before "Load Theirs" replaced it.
        case conflict
        /// The text before an older version was restored.
        case restore
        /// Before an AI edit (#19).
        case intelligence
    }

    public var id: UUID
    public var date: Date
    public var reason: Reason
    /// The text's length in bytes.
    public var size: Int
}

/// Keeps earlier versions of each file in Application Support, never next to the file.
/// Versions older than `maxAge` are dropped, except the newest `minimumKept`, and each file
/// keeps at most `maxCount`.
public final class VersionStore: @unchecked Sendable {
    public static let standard = VersionStore(
        folder: URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "computer.srcery.grimoire", directoryHint: .isDirectory)
            .appending(path: "Versions", directoryHint: .isDirectory))

    public let folder: URL
    public var maxAge: TimeInterval = 14 * 24 * 60 * 60
    public var maxCount = 200
    public var minimumKept = 10
    /// How long the file must have gone unsaved before a save keeps the old text.
    public var pause: TimeInterval = 120

    private let lock = NSLock()
    /// When each file was last saved, to tell a pause from steady typing.
    private var lastSave: [String: Date] = [:]

    public init(folder: URL) {
        self.folder = folder
    }

    // MARK: - Keeping versions

    /// Called before a save overwrites `previous` (the text on disk). Keeps it when this is
    /// the first save after a pause.
    public func willSave(_ url: URL, previous: String, now: Date = Date()) {
        let key = Self.key(for: url)
        let last = lock.withLock { () -> Date? in
            defer { lastSave[key] = now }
            return lastSave[key]
        }
        guard last.map({ now.timeIntervalSince($0) >= pause }) ?? true else { return }
        keep(previous, of: url, reason: .edit, now: now)
    }

    /// Keeps `text` as a version of `url`, unless it matches the newest one already kept.
    @discardableResult
    public func keep(_ text: String, of url: URL, reason: Version.Reason, now: Date = Date()) -> Version? {
        let data = Data(text.utf8)
        return lock.withLock {
            var versions = load(url)
            if let newest = versions.first, newest.size == data.count, read(newest, of: url) == data { return nil }
            let version = Version(id: UUID(), date: now, reason: reason, size: data.count)
            let directory = self.directory(for: url)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: directory.appending(path: version.id.uuidString + ".md"), options: .atomic)
            } catch {
                return nil
            }
            versions.insert(version, at: 0)
            versions = prune(versions, of: url, now: now)
            save(versions, of: url)
            return version
        }
    }

    // MARK: - Reading

    /// Every kept version of `url`, newest first.
    public func versions(of url: URL) -> [Version] {
        lock.withLock { load(url) }
    }

    public func text(of version: Version, for url: URL) -> String? {
        lock.withLock { read(version, of: url).map { String(decoding: $0, as: UTF8.self) } }
    }

    /// A file was renamed or moved; its history goes with it.
    public func move(from old: URL, to new: URL) {
        lock.withLock {
            let source = directory(for: old)
            let destination = directory(for: new)
            guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else { return }
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: source, to: destination)
            if let date = lastSave.removeValue(forKey: Self.key(for: old)) { lastSave[Self.key(for: new)] = date }
        }
    }

    // MARK: - Storage

    private static func key(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
    }

    /// One folder per file, named by a hash of its path.
    private func directory(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(Self.key(for: url).utf8))
        let name = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return folder.appending(path: name, directoryHint: .isDirectory)
    }

    private struct Index: Codable {
        var path: String
        var versions: [Version]
    }

    private func load(_ url: URL) -> [Version] {
        let file = directory(for: url).appending(path: "index.json")
        guard let data = try? Data(contentsOf: file),
            let index = try? JSONDecoder.versions.decode(Index.self, from: data)
        else { return [] }
        return index.versions
    }

    private func save(_ versions: [Version], of url: URL) {
        let index = Index(path: Self.key(for: url), versions: versions)
        guard let data = try? JSONEncoder.versions.encode(index) else { return }
        try? data.write(to: directory(for: url).appending(path: "index.json"), options: .atomic)
    }

    private func read(_ version: Version, of url: URL) -> Data? {
        try? Data(contentsOf: directory(for: url).appending(path: version.id.uuidString + ".md"))
    }

    /// Drops versions past the age and count limits, keeping the newest few whatever their age.
    private func prune(_ versions: [Version], of url: URL, now: Date) -> [Version] {
        var kept: [Version] = []
        for (position, version) in versions.enumerated() {
            let young = now.timeIntervalSince(version.date) <= maxAge
            if position < maxCount, young || position < minimumKept {
                kept.append(version)
            } else {
                try? FileManager.default.removeItem(
                    at: directory(for: url).appending(path: version.id.uuidString + ".md"))
            }
        }
        return kept
    }
}

extension JSONEncoder {
    fileprivate static var versions: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    fileprivate static var versions: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
