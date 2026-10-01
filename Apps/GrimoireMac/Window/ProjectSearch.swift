import GrimoireCore
import GrimoireIntelligence
import SwiftUI

/// Find in Project (⇧⌘E): a query over every page in the window's project, with results
/// listed in the sidebar by file.
@MainActor @Observable
final class ProjectSearch {
    var isActive = false
    var query = "" {
        didSet { if query != oldValue { schedule() } }
    }
    var caseSensitive = false {
        didSet { if caseSensitive != oldValue { schedule() } }
    }
    var regex = false {
        didSet { if regex != oldValue { schedule() } }
    }
    var wholeWord = false {
        didSet { if wholeWord != oldValue { schedule() } }
    }
    private(set) var results: [FileMatches] = []
    /// Passages that match the query's meaning without containing it, when intelligence is on.
    private(set) var related: [PassageHit] = []
    private(set) var isSearching = false
    /// Bumped to ask the search field to take focus.
    private(set) var focusRequest = 0

    @ObservationIgnored var index: ProjectIndex?
    @ObservationIgnored var semantic: (() -> SemanticIndex?)?
    @ObservationIgnored private var task: Task<Void, Never>?

    var search: TextSearch {
        TextSearch(query, caseSensitive: caseSensitive, regex: regex, wholeWord: wholeWord)
    }

    var matchCount: Int { results.reduce(0) { $0 + $1.matches.count } }

    func begin(with query: String? = nil) {
        if let query, !query.isEmpty { self.query = query }
        isActive = true
        focusRequest += 1
        schedule()
    }

    func end() {
        isActive = false
        task?.cancel()
    }

    /// Searches again after a short pause in typing, or now when the index changed.
    func schedule(after delay: Duration = .milliseconds(120)) {
        task?.cancel()
        guard isActive, let index, !search.isInvalid, !query.isEmpty else {
            results = []
            related = []
            isSearching = false
            return
        }
        let semantic = regex ? nil : semantic?()
        let search = search
        isSearching = true
        task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await index.waitUntilRead()
            let results = await index.search(search)
            guard !Task.isCancelled, let self else { return }
            self.results = results
            self.related = await Self.related(to: search.query, in: semantic)
            self.isSearching = false
        }
    }

    /// The best passages by meaning that don't contain the query itself (those are in the
    /// results already). Only for queries of a few letters or more.
    private static func related(to query: String, in index: SemanticIndex?) async -> [PassageHit] {
        guard let index, query.count >= 4 else { return [] }
        let hits = await index.search(query, limit: 12)
        return Array(
            hits.filter { $0.score >= 0.3 && $0.passage.text.range(of: query, options: .caseInsensitive) == nil }
                .prefix(5))
    }
}
