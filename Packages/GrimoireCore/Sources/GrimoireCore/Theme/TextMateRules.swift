/// A theme's `tokenColors`: TextMate scope selectors with the style each one sets, matched
/// against a stack of scopes the way VS Code does.
struct TextMateRules {
    struct Rule: Sendable {
        /// Each selector is a path of scopes, outermost first: `text.html.markdown markup.bold`.
        var selectors: [[String]]
        var foreground: String?
        var background: String?
        /// `bold italic underline strikethrough`, or empty to clear them.
        var fontStyle: String?
    }

    var rules: [Rule] = []
    /// The entries as read, so a theme that `include`s this one can build on them.
    var entries: [[String: Any]]
    /// The settings of a rule with no scope: the theme's default text and background.
    var defaultForeground: String?
    var defaultBackground: String?

    /// Reads a `tokenColors` array (or the `settings` array of a `.tmTheme`).
    init(_ entries: [[String: Any]]) {
        self.entries = entries
        for entry in entries {
            guard let settings = entry["settings"] as? [String: Any] else { continue }
            let foreground = settings["foreground"] as? String
            let background = settings["background"] as? String
            let fontStyle = settings["fontStyle"] as? String
            let scopes: [String]
            if let scope = entry["scope"] as? String {
                scopes = scope.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            } else if let list = entry["scope"] as? [String] {
                scopes = list.flatMap { $0.split(separator: ",") }.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                if defaultForeground == nil { defaultForeground = foreground }
                if defaultBackground == nil { defaultBackground = background }
                continue
            }
            let selectors =
                scopes
                .filter { !$0.isEmpty && !$0.contains(" -") && !$0.hasPrefix("-") }
                .map { $0.split(separator: " ").map(String.init).filter { $0 != ">" } }
                .filter { !$0.isEmpty }
            guard !selectors.isEmpty else { continue }
            rules.append(
                Rule(selectors: selectors, foreground: foreground, background: background, fontStyle: fontStyle))
        }
    }

    /// The settings that apply to the innermost scope of `stack`. Each setting comes from
    /// the most specific rule that sets it; later rules win ties. Nil when nothing matches.
    func match(_ stack: [String]) -> Match? {
        var best: [Int: Score] = [:]
        var found = Match()
        for (order, rule) in rules.enumerated() {
            guard let score = rule.selectors.compactMap({ Self.score($0, stack, order: order) }).max() else {
                continue
            }
            if let foreground = rule.foreground, score > best[0, default: .none] {
                best[0] = score
                found.foreground = foreground
            }
            if let background = rule.background, score > best[1, default: .none] {
                best[1] = score
                found.background = background
            }
            if let fontStyle = rule.fontStyle, score > best[2, default: .none] {
                best[2] = score
                found.fontStyle = fontStyle
            }
        }
        if found.foreground == nil, found.background == nil, found.fontStyle == nil { return nil }
        return found
    }

    /// The settings a scope stack ends up with.
    struct Match: Equatable {
        var foreground: String?
        var background: String?
        var fontStyle: String?
    }

    /// How deep and how specific a match is, compared in that order, then rule order.
    struct Score: Comparable {
        var depth: Int
        var segments: Int
        var parents: Int
        var order: Int

        static let none = Score(depth: -1, segments: 0, parents: 0, order: -1)

        static func < (lhs: Score, rhs: Score) -> Bool {
            (lhs.depth, lhs.segments, lhs.parents, lhs.order) < (rhs.depth, rhs.segments, rhs.parents, rhs.order)
        }
    }

    /// Where `selector` matches `stack`: its last scope must match a scope in the stack and
    /// any scopes before it must match outer scopes, in order.
    static func score(_ selector: [String], _ stack: [String], order: Int) -> Score? {
        guard let target = selector.last else { return nil }
        for depth in stride(from: stack.count - 1, through: 0, by: -1) where matches(target, stack[depth]) {
            var parentIndex = depth - 1
            var parentsMatched = true
            for parent in selector.dropLast().reversed() {
                while parentIndex >= 0, !matches(parent, stack[parentIndex]) { parentIndex -= 1 }
                if parentIndex < 0 {
                    parentsMatched = false
                    break
                }
                parentIndex -= 1
            }
            guard parentsMatched else { continue }
            return Score(
                depth: depth, segments: target.split(separator: ".").count, parents: selector.count - 1, order: order)
        }
        return nil
    }

    /// `markup.heading` matches `markup.heading` and `markup.heading.markdown`, not
    /// `markup.headings`.
    static func matches(_ selector: String, _ scope: String) -> Bool {
        scope == selector || scope.hasPrefix(selector + ".")
    }
}
