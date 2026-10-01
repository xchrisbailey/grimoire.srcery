import Foundation

/// A find query: plain or a regular expression, optionally case sensitive or whole words
/// only. Offsets are UTF-16.
public struct TextSearch: Equatable, Sendable {
    public var query: String
    public var caseSensitive: Bool
    public var regex: Bool
    public var wholeWord: Bool

    public init(_ query: String, caseSensitive: Bool = false, regex: Bool = false, wholeWord: Bool = false) {
        self.query = query
        self.caseSensitive = caseSensitive
        self.regex = regex
        self.wholeWord = wholeWord
    }

    /// The compiled pattern, or nil for an empty query or an invalid regular expression.
    public var expression: NSRegularExpression? {
        guard !query.isEmpty else { return nil }
        var pattern = regex ? query : NSRegularExpression.escapedPattern(for: query)
        if wholeWord { pattern = "\\b(?:" + pattern + ")\\b" }
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if !caseSensitive { options.insert(.caseInsensitive) }
        return try? NSRegularExpression(pattern: pattern, options: options)
    }

    /// Whether the query is a regular expression that doesn't compile.
    public var isInvalid: Bool { !query.isEmpty && expression == nil }

    /// Every match in `text`, in order. Empty matches (a regex like `^`) are skipped.
    public func matches(in text: String, limit: Int = .max) -> [NSRange] {
        guard let expression else { return [] }
        var ranges: [NSRange] = []
        let whole = NSRange(location: 0, length: (text as NSString).length)
        expression.enumerateMatches(in: text, range: whole) { result, _, stop in
            guard let range = result?.range, range.length > 0 else { return }
            ranges.append(range)
            if ranges.count >= limit { stop.pointee = true }
        }
        return ranges
    }

    /// What `match` (a range from `matches`) becomes: the replacement as typed, or with
    /// `$1`-style groups filled in for a regular expression.
    public func replacement(for match: NSRange, in text: String, template: String) -> String {
        guard regex, let expression,
            let result = expression.firstMatch(in: text, range: match), result.range == match
        else { return template }
        return expression.replacementString(for: result, in: text, offset: 0, template: template)
    }
}
