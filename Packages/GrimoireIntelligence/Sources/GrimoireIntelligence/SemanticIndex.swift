import Foundation
import GrimoireCore
import NaturalLanguage
import Observation
import Synchronization

/// A piece of a page small enough to embed and to quote: a few paragraphs under a heading.
public struct Passage: Codable, Hashable, Sendable {
    public var url: URL
    /// The page's path in the project, for showing: `notes/potions.md`.
    public var path: String
    /// The nearest heading above, if any.
    public var heading: String?
    /// Where the passage starts in the page (UTF-16), to open the page at it.
    public var location: Int
    public var text: String
}

/// A passage found for a query, best first.
public struct PassageHit: Hashable, Sendable, Identifiable {
    public var passage: Passage
    public var score: Double
    public var id: String { passage.url.path(percentEncoded: false) + "#\(passage.location)" }
}

/// One page to index: the project index's copy of its text.
public struct IndexSource: Sendable {
    public var url: URL
    public var path: String
    public var modified: Date
    public var text: String

    public init(url: URL, path: String, modified: Date, text: String) {
        self.url = url
        self.path = path
        self.modified = modified
        self.text = text
    }
}

/// Meaning-based search over a project's pages, on the device.
///
/// Pages are split into passages and each is embedded with NaturalLanguage's sentence
/// embedding. The vectors are saved in Application Support, one file per project, so only
/// changed pages are embedded again. A query is embedded the same way and passages are
/// ranked by cosine similarity, nudged up when they contain the query's words.
@MainActor @Observable
public final class SemanticIndex {
    /// Whether pages are still being embedded.
    public private(set) var isIndexing = false
    /// How many passages are searchable.
    public private(set) var passageCount = 0

    @ObservationIgnored private var store = SemanticStore()
    @ObservationIgnored private let file: URL?
    @ObservationIgnored private var indexing: Task<Void, Never>?

    /// `file` is where the vectors are kept; nil keeps them in memory only.
    public init(file: URL?) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file),
            let saved = try? JSONDecoder().decode(SemanticStore.self, from: data),
            saved.version == SemanticStore.version
        {
            store = saved
            passageCount = store.pages.values.reduce(0) { $0 + $1.passages.count }
        }
    }

    /// The index file for project `id`, in Application Support.
    public static func file(for id: UUID) -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return support.appending(path: "Grimoire/Semantic/\(id.uuidString).json")
    }

    /// Whether this Mac has the sentence embedding the index needs.
    public nonisolated static var isAvailable: Bool { NLEmbedding.sentenceEmbedding(for: .english) != nil }

    /// Embeds pages that are new or changed and drops pages that are gone.
    public func update(from sources: [IndexSource]) {
        indexing?.cancel()
        let known = store.pages.mapValues(\.modified)
        let urls = Set(sources.map(\.url))
        store.pages = store.pages.filter { urls.contains($0.key) }
        let changed = sources.filter { known[$0.url] != $0.modified }
        passageCount = store.pages.values.reduce(0) { $0 + $1.passages.count }
        guard !changed.isEmpty else {
            save()
            return
        }
        isIndexing = true
        indexing = Task { [weak self] in
            let pages = await Task.detached(priority: .utility) { Self.embed(changed) }.value
            guard !Task.isCancelled, let self else { return }
            for (url, page) in pages { self.store.pages[url] = page }
            self.passageCount = self.store.pages.values.reduce(0) { $0 + $1.passages.count }
            self.isIndexing = false
            self.save()
        }
    }

    /// Waits for embedding to finish; for tests and for asking right after opening.
    public func waitUntilIndexed() async {
        await indexing?.value
    }

    /// The passages that best match `query`.
    public func search(_ query: String, limit: Int = 8) async -> [PassageHit] {
        let snapshot = snapshot
        return await Task.detached(priority: .userInitiated) { snapshot.search(query, limit: limit) }.value
    }

    /// The index as it is now, to search off the main thread.
    public var snapshot: SemanticSnapshot {
        SemanticSnapshot(entries: store.pages.values.flatMap { page in page.passages })
    }

    private func save() {
        guard let file else { return }
        let store = store
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(store) { try? data.write(to: file, options: .atomic) }
        }
    }

    // MARK: - Embedding

    /// Embeds `sources` across a few threads, each with its own embedding.
    nonisolated static func embed(_ sources: [IndexSource]) -> [URL: SemanticStore.Page] {
        let workers = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 1))
        let pages = Mutex<[URL: SemanticStore.Page]>([:])
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return }
            for index in stride(from: worker, to: sources.count, by: workers) {
                if Task.isCancelled { return }
                let source = sources[index]
                let passages = PassageSplitter.passages(in: source.text, url: source.url, path: source.path)
                let embedded = passages.compactMap { passage in
                    embedding.vector(for: embeddingText(passage)).map {
                        SemanticStore.Entry(passage: passage, vector: Vector($0))
                    }
                }
                let page = SemanticStore.Page(modified: source.modified, passages: embedded)
                pages.withLock { $0[source.url] = page }
            }
        }
        return pages.withLock { $0 }
    }

    /// The heading carries meaning too, so it's embedded with the passage.
    nonisolated static func embeddingText(_ passage: Passage) -> String {
        let text = String(passage.text.prefix(1_000))
        return passage.heading.map { $0 + "\n" + text } ?? text
    }
}

/// The index's passages and vectors, as a value to search on any thread.
public struct SemanticSnapshot: Sendable {
    var entries: [SemanticStore.Entry]

    public var isEmpty: Bool { entries.isEmpty }

    /// The passages that best match `query`, best first.
    public func search(_ query: String, limit: Int) -> [PassageHit] {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english),
            let vector = embedding.vector(for: query).map(Vector.init)
        else { return [] }
        let terms = Self.terms(in: query)
        var hits = entries.map { entry in
            let semantic = entry.vector.cosine(vector)
            let words = Self.terms(in: entry.passage.text + " " + (entry.passage.heading ?? ""))
            let overlap = terms.isEmpty ? 0 : Double(terms.intersection(words).count) / Double(terms.count)
            return PassageHit(passage: entry.passage, score: semantic + 0.25 * overlap)
        }
        hits.sort { $0.score > $1.score }
        return Array(hits.prefix(limit))
    }

    /// The meaningful words in `text`, lowercased.
    static func terms(in text: String) -> Set<String> {
        var words = Set<String>()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = text[range].lowercased()
            if word.count > 2, !stopWords.contains(word) { words.insert(word) }
            return true
        }
        return words
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "are", "was", "were", "what", "where", "when", "which", "who", "how", "why", "did", "does",
        "about", "with", "this", "that", "from", "into", "have", "has", "had", "you", "your", "can", "any", "all",
        "write", "wrote", "written", "notes", "note", "page", "pages", "say", "said", "there", "their", "they",
    ]
}

/// The saved index: each page's modification date and its embedded passages.
struct SemanticStore: Codable, Sendable {
    static let version = 1

    struct Entry: Codable, Sendable {
        var passage: Passage
        var vector: Vector
    }

    struct Page: Codable, Sendable {
        var modified: Date
        var passages: [Entry]
    }

    var version = Self.version
    var pages: [URL: Page] = [:]
}

/// An embedding vector, unit length, saved compactly as Float bytes.
struct Vector: Codable, Sendable {
    var values: [Float]

    init(_ doubles: [Double]) {
        let norm = sqrt(doubles.reduce(0) { $0 + $1 * $1 })
        values = doubles.map { Float(norm > 0 ? $0 / norm : 0) }
    }

    func cosine(_ other: Vector) -> Double {
        guard values.count == other.values.count else { return 0 }
        var sum: Float = 0
        for index in values.indices { sum += values[index] * other.values[index] }
        return Double(sum)
    }

    init(from decoder: Decoder) throws {
        let data = try decoder.singleValueContainer().decode(Data.self)
        values = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values.withUnsafeBufferPointer { Data(buffer: $0) })
    }
}

/// Splits a markdown page into passages: sections under headings, cut at paragraphs into
/// pieces of a few hundred characters. Frontmatter and code fences' contents stay with
/// their section but never start a heading.
enum PassageSplitter {
    static let targetLength = 700

    static func passages(in text: String, url: URL, path: String) -> [Passage] {
        var passages: [Passage] = []
        var heading: String?
        var current = ""
        var start = 0
        // A section's first passage opens the page at its heading.
        var headingStart: Int?
        var offset = 0
        var inFence = false
        var inFrontmatter = false

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                passages.append(Passage(url: url, path: path, heading: heading, location: start, text: trimmed))
            }
            current = ""
        }

        for (number, line) in text.components(separatedBy: "\n").enumerated() {
            let length = line.utf16.count + 1
            defer { offset += length }
            if number == 0, line == "---" {
                inFrontmatter = true
                continue
            }
            if inFrontmatter {
                if line == "---" || line == "..." { inFrontmatter = false }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle() }
            if !inFence, let title = headingText(trimmed) {
                flush()
                heading = title
                headingStart = offset
                continue
            }
            if trimmed.isEmpty, !inFence, current.count >= targetLength { flush() }
            if current.isEmpty {
                guard !trimmed.isEmpty else { continue }
                start = headingStart ?? offset
                headingStart = nil
            }
            current += line + "\n"
        }
        flush()
        return passages
    }

    private static func headingText(_ line: String) -> String? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }
        guard hashes.count <= 6, line.dropFirst(hashes.count).first == " " else { return nil }
        return line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
    }
}
