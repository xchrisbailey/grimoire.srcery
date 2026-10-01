import GrimoireCore
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
    private(set) var isSearching = false
    /// Bumped to ask the search field to take focus.
    private(set) var focusRequest = 0

    @ObservationIgnored var index: ProjectIndex?
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
            isSearching = false
            return
        }
        let search = search
        isSearching = true
        task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await index.waitUntilRead()
            let results = await index.search(search)
            guard !Task.isCancelled, let self else { return }
            self.results = results
            self.isSearching = false
        }
    }
}
