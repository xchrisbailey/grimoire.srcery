import Foundation
import FoundationModels
import GrimoireCore

/// An answer about the project, with the passages it may cite. `[n]` in the text refers to
/// `sources[n - 1]`.
public struct ProjectAnswer: Equatable, Sendable {
    public var text: String
    public var sources: [PassageHit]

    public init(text: String, sources: [PassageHit]) {
        self.text = text
        self.sources = sources
    }

    /// The source numbers the text cites, in order of first mention.
    public var citedNumbers: [Int] {
        var seen: [Int] = []
        let pattern = /\[(\d+)\]/
        for match in text.matches(of: pattern) {
            if let number = Int(match.1), (1...sources.count).contains(number), !seen.contains(number) {
                seen.append(number)
            }
        }
        return seen
    }
}

@MainActor
extension IntelligenceService {
    /// Answers `question` from the project's notes: the best passages go in with the
    /// question, and the model can search for more. Streams the answer as it's written.
    public func answer(_ question: String, from index: SemanticIndex) -> AsyncThrowingStream<ProjectAnswer, Error> {
        let (stream, continuation) = AsyncThrowingStream<ProjectAnswer, Error>.makeStream()
        let task = Task { @MainActor in
            do {
                await index.waitUntilIndexed()
                let snapshot = index.snapshot
                let sources = SourceList(snapshot.search(question, limit: 5))
                guard !sources.all.isEmpty else {
                    continuation.yield(
                        ProjectAnswer(
                            text: String(localized: "There's nothing in this project's pages about that yet."),
                            sources: []))
                    continuation.finish()
                    return
                }
                let request = IntelligenceRequest(
                    instructions: Prompts.projectAnswer,
                    text: "Question: \(question)\n\nNotes:\n\n" + sources.numbered(sources.all),
                    tools: [SearchNotesTool(snapshot: snapshot, sources: sources)], temperature: 0.2)
                for try await text in self.stream(request) {
                    continuation.yield(ProjectAnswer(text: text, sources: sources.all))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}

extension Prompts {
    static let projectAnswer = """
        You answer questions about the user's own notes, using only the numbered notes given and any \
        you find with the searchNotes tool. Answer in a few plain sentences. After each fact, cite the \
        note it came from with its number in brackets, like [2]. If the notes don't answer the \
        question, say so in one sentence.
        """
}

/// The passages an answer can cite, numbered in the order they were found. Shared with the
/// search tool, which runs off the main thread.
final class SourceList: @unchecked Sendable {
    private let lock = NSLock()
    private var hits: [PassageHit]

    init(_ hits: [PassageHit]) { self.hits = hits }

    var all: [PassageHit] { lock.withLock { hits } }

    /// Adds `found`, skipping passages already listed; returns them with their numbers.
    func add(_ found: [PassageHit]) -> [(Int, PassageHit)] {
        lock.withLock {
            var added: [(Int, PassageHit)] = []
            for hit in found where !hits.contains(where: { $0.id == hit.id }) {
                hits.append(hit)
                added.append((hits.count, hit))
            }
            return added
        }
    }

    func numbered(_ hits: [PassageHit], from first: Int = 1) -> String {
        hits.enumerated().map { Self.format(first + $0, $1) }.joined(separator: "\n\n")
    }

    static func format(_ number: Int, _ hit: PassageHit) -> String {
        let place = [hit.passage.path, hit.passage.heading].compactMap { $0 }.joined(separator: " › ")
        return "[\(number)] \(place)\n\(hit.passage.text.prefix(600))"
    }
}

/// Lets the model look for more notes while it answers.
struct SearchNotesTool: Tool {
    let name = "searchNotes"
    let description = "Searches the user's notes and returns numbered passages to cite."
    let snapshot: SemanticSnapshot
    let sources: SourceList

    @Generable
    struct Arguments {
        @Guide(description: "What to look for, in a few words")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let added = sources.add(snapshot.search(arguments.query, limit: 3))
        guard !added.isEmpty else { return "No other notes match." }
        return added.map { SourceList.format($0.0, $0.1) }.joined(separator: "\n\n")
    }
}
