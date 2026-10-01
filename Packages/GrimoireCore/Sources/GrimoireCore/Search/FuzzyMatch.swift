import Foundation

/// Fuzzy matching for quick open and Incantations: the query's characters must appear in
/// order; consecutive runs, word starts and an early first match score higher.
public enum FuzzyMatch {
    /// A score (higher is better) and the matched character offsets, or nil when `query`
    /// isn't a subsequence of `candidate`. An empty query matches everything with score 0.
    public static func score(_ query: String, in candidate: String) -> (score: Int, matches: [Int])? {
        let needle = Array(query.lowercased().filter { $0 != " " })
        guard !needle.isEmpty else { return (0, []) }
        let original = Array(candidate)
        let haystack = Array(candidate.lowercased())
        guard haystack.count == original.count else { return plainScore(needle, haystack) }
        var matches: [Int] = []
        var score = 0
        var index = 0
        var previous = -2
        for character in needle {
            while index < haystack.count, haystack[index] != character { index += 1 }
            guard index < haystack.count else { return nil }
            var points = 1
            if index == previous + 1 { points += 5 }
            if index == 0 || isBoundary(original, at: index) { points += 8 }
            score += points
            matches.append(index)
            previous = index
            index += 1
        }
        // Prefer matches that start early and candidates that are short.
        score -= min(matches.first ?? 0, 20)
        score -= haystack.count / 10
        return (score, matches)
    }

    private static func plainScore(_ needle: [Character], _ haystack: [Character]) -> (score: Int, matches: [Int])? {
        var index = 0
        var matches: [Int] = []
        for character in needle {
            while index < haystack.count, haystack[index] != character { index += 1 }
            guard index < haystack.count else { return nil }
            matches.append(index)
            index += 1
        }
        return (needle.count, matches)
    }

    /// A word start: after a separator, or an uppercase letter after a lowercase one.
    private static func isBoundary(_ characters: [Character], at index: Int) -> Bool {
        let before = characters[index - 1]
        if " /-_.".contains(before) { return true }
        return before.isLowercase && characters[index].isUppercase
    }

    /// `items` that match `query`, best first; ties keep their order.
    public static func rank<Item>(_ items: [Item], by query: String, text: (Item) -> String) -> [Item] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        return items.enumerated()
            .compactMap { offset, item in score(query, in: text(item)).map { (item, $0.score, offset) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }
}
