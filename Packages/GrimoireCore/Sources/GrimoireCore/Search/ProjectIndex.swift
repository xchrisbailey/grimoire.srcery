import Foundation
import Observation

/// One file the index knows: where it is and how to show it.
public struct IndexedDocument: Identifiable, Hashable, Sendable {
    public var url: URL
    /// The file name without its extension.
    public var name: String
    /// The path inside its bound folder, starting with the folder's name: `notes/potions.md`.
    public var path: String

    public var id: URL { url }
}

/// One match in a file, with its line for showing in results.
public struct LineMatch: Hashable, Sendable {
    /// The match in the whole file (UTF-16).
    public var range: NSRange
    /// 1-based line number.
    public var line: Int
    /// The line's text, trimmed to a readable length around the match.
    public var preview: String
    /// The match inside `preview`.
    public var previewRange: NSRange
}

/// A document the index has read, with when it last changed and its text.
public struct ReadDocument: Sendable {
    public var document: IndexedDocument
    public var modified: Date
    public var text: String
}

public struct FileMatches: Identifiable, Hashable, Sendable {
    public var document: IndexedDocument
    public var matches: [LineMatch]

    public var id: URL { document.url }
}

/// Every document in an open project with its text, read in the background and kept
/// current as the file trees change, for quick open and project search.
@MainActor @Observable
public final class ProjectIndex {
    /// The project's documents, ordered by path.
    public private(set) var documents: [IndexedDocument] = []
    /// Whether file contents are still being read.
    public private(set) var isReading = false

    /// Called each time new or changed files have been read.
    @ObservationIgnored public var onRead: (() -> Void)?

    @ObservationIgnored private var texts: [URL: (modified: Date, text: String)] = [:]
    @ObservationIgnored private var reading: Task<Void, Never>?

    public init() {}

    /// Takes the current trees: lists their documents and rereads any file that changed.
    public func update(from folders: [BoundFolder]) {
        var documents: [IndexedDocument] = []
        for folder in folders {
            guard let tree = folder.tree, let root = folder.url else { continue }
            let rootPath = root.standardizedFileURL.path(percentEncoded: false)
            for node in tree.documents {
                let full = node.url.standardizedFileURL.path(percentEncoded: false)
                let relative = full.hasPrefix(rootPath) ? String(full.dropFirst(rootPath.count)) : node.name
                let path = folder.root.displayName + "/" + relative.trimmingPrefix("/")
                documents.append(
                    IndexedDocument(url: node.url, name: node.url.deletingPathExtension().lastPathComponent, path: path)
                )
            }
        }
        documents.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        self.documents = documents
        readChanged()
    }

    /// Reads files that are new or changed since they were last read, off the main thread.
    private func readChanged() {
        reading?.cancel()
        let known = texts.mapValues(\.modified)
        let urls = documents.map(\.url)
        texts = texts.filter { url, _ in urls.contains(url) }
        isReading = true
        reading = Task { [weak self] in
            let fresh = await Task.detached(priority: .utility) { Self.read(urls, known: known) }.value
            guard !Task.isCancelled, let self else { return }
            for (url, entry) in fresh { self.texts[url] = entry }
            self.isReading = false
            self.onRead?()
        }
    }

    private nonisolated static func read(_ urls: [URL], known: [URL: Date]) -> [URL: (modified: Date, text: String)] {
        var fresh: [URL: (modified: Date, text: String)] = [:]
        for url in urls {
            guard !Task.isCancelled else { break }
            // Not URL resource values: those are cached on the URL and miss later edits.
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
            let modified = attributes?[.modificationDate] as? Date ?? .distantPast
            if let date = known[url], date == modified { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            fresh[url] = (modified, String(decoding: data, as: UTF8.self))
        }
        return fresh
    }

    /// Waits until every file has been read; for tests and for searching right after opening.
    public func waitUntilRead() async {
        await reading?.value
    }

    /// Searches every document's text. Results keep the documents' order, with at most
    /// `limit` matches in all.
    public func search(_ search: TextSearch, limit: Int = 2_000) async -> [FileMatches] {
        let snapshot = documents.compactMap { document in texts[document.url].map { (document, $0.text) } }
        return await Task.detached(priority: .userInitiated) {
            var results: [FileMatches] = []
            var total = 0
            for (document, text) in snapshot where total < limit {
                let ranges = search.matches(in: text, limit: limit - total)
                guard !ranges.isEmpty else { continue }
                total += ranges.count
                results.append(FileMatches(document: document, matches: Self.lineMatches(ranges, in: text)))
            }
            return results
        }.value
    }

    /// Every document that has been read, with when it last changed and its text.
    public var readDocuments: [ReadDocument] {
        documents.compactMap { document in
            texts[document.url].map { ReadDocument(document: document, modified: $0.modified, text: $0.text) }
        }
    }

    /// The text the index holds for `url`, if it has read it.
    public func text(of url: URL) -> String? {
        texts[url]?.text
    }

    nonisolated static func lineMatches(_ ranges: [NSRange], in text: String) -> [LineMatch] {
        let string = text as NSString
        var line = 1
        var scanned = 0
        return ranges.map { range in
            // Count line breaks up to this match, continuing from the last one.
            var index = scanned
            while index < range.location {
                if string.character(at: index) == 10 { line += 1 }
                index += 1
            }
            scanned = range.location
            let lineRange = string.lineRange(for: NSRange(location: range.location, length: 0))
            var content = string.substring(with: lineRange).trimmingCharacters(in: .newlines)
            var start = range.location - lineRange.location
            // Keep long lines readable: up to 40 characters before the match.
            let leading = content.prefix { $0 == " " || $0 == "\t" }.utf16.count
            let cut = max(leading, start - 40)
            if cut > 0 {
                content = String((content as NSString).substring(from: cut))
                start -= cut
                if cut > leading {
                    content = "…" + content
                    start += 1
                }
            }
            let length = min(range.length, (content as NSString).length - start)
            return LineMatch(
                range: range, line: line, preview: String(content.prefix(240)),
                previewRange: NSRange(location: start, length: max(0, length)))
        }
    }
}
