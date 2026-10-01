import Foundation
import GrimoireCore

/// One command in the Spells menu (`/`), the ⌘K Incantations palette (#14) and, on iOS,
/// the keyboard accessory bar.
public struct Spell: Identifiable, Hashable, Sendable {
    public enum Effect: Hashable, Sendable {
        /// Re-casts the caret's line as another kind of block, keeping its text.
        case turnInto(BlockKind)
        /// A fenced code block; the editor then offers a language.
        case codeBlock
        case table
        case divider
        /// Picks an image file and copies it into `assets/`.
        case image
        case link
        /// A GitHub alert: `> [!NOTE]`.
        case callout
        /// Today's date, inline.
        case date
        /// YAML frontmatter at the top of the file.
        case frontmatter
    }

    public let id: String
    public let title: String
    public let subtitle: String
    /// Other names the filter matches, like `h1` or `todo`.
    public let aliases: [String]
    /// SF Symbol name.
    public let icon: String
    /// A hint shown at the row's end, such as the markdown it writes.
    public let hint: String
    public let effect: Effect

    public init(
        id: String, title: String, subtitle: String, aliases: [String] = [], icon: String, hint: String = "",
        effect: Effect
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.aliases = aliases
        self.icon = icon
        self.hint = hint
        self.effect = effect
    }
}

/// The spells Grimoire knows, in menu order.
public enum Spellbook {
    public static let standard: [Spell] = [
        Spell(
            id: "text", title: String(localized: "Text"), subtitle: String(localized: "Plain paragraph"),
            aliases: ["paragraph", "plain", "p"], icon: "text.alignleft", effect: .turnInto(.paragraph)),
        Spell(
            id: "h1", title: String(localized: "Heading 1"), subtitle: String(localized: "Large section heading"),
            aliases: ["heading", "title", "#"], icon: "textformat.size.larger", hint: "#",
            effect: .turnInto(.heading(level: 1))),
        Spell(
            id: "h2", title: String(localized: "Heading 2"), subtitle: String(localized: "Medium section heading"),
            aliases: ["heading", "subtitle", "##"], icon: "textformat.size", hint: "##",
            effect: .turnInto(.heading(level: 2))),
        Spell(
            id: "h3", title: String(localized: "Heading 3"), subtitle: String(localized: "Small section heading"),
            aliases: ["heading", "###"], icon: "textformat.size.smaller", hint: "###",
            effect: .turnInto(.heading(level: 3))),
        Spell(
            id: "bullet", title: String(localized: "Bullet list"), subtitle: String(localized: "A simple list"),
            aliases: ["list", "ul", "unordered", "-"], icon: "list.bullet", hint: "-",
            effect: .turnInto(.listItem(.bullet))),
        Spell(
            id: "numbered", title: String(localized: "Numbered list"), subtitle: String(localized: "A list in order"),
            aliases: ["list", "ol", "ordered", "1."], icon: "list.number", hint: "1.",
            effect: .turnInto(.listItem(.ordered()))),
        Spell(
            id: "todo", title: String(localized: "To-do"), subtitle: String(localized: "Checkboxes"),
            aliases: ["task", "checkbox", "check", "[]"], icon: "checklist", hint: "[ ]",
            effect: .turnInto(.listItem(.task))),
        Spell(
            id: "quote", title: String(localized: "Quote"), subtitle: String(localized: "Set a passage apart"),
            aliases: ["blockquote", ">"], icon: "text.quote", hint: ">", effect: .turnInto(.blockquote)),
        Spell(
            id: "code", title: String(localized: "Code block"),
            subtitle: String(localized: "Fenced code with a language"),
            aliases: ["fence", "snippet", "```"], icon: "chevron.left.forwardslash.chevron.right", hint: "```",
            effect: .codeBlock),
        Spell(
            id: "table", title: String(localized: "Table"), subtitle: String(localized: "Rows and columns"),
            aliases: ["grid"], icon: "tablecells", hint: "/table", effect: .table),
        Spell(
            id: "divider", title: String(localized: "Divider"), subtitle: String(localized: "A horizontal rule"),
            aliases: ["rule", "hr", "separator", "---"], icon: "minus", hint: "---", effect: .divider),
        Spell(
            id: "image", title: String(localized: "Image"), subtitle: String(localized: "Copy a picture into assets"),
            aliases: ["picture", "photo", "img"], icon: "photo", effect: .image),
        Spell(
            id: "link", title: String(localized: "Link"), subtitle: String(localized: "Text that goes somewhere"),
            aliases: ["url", "href"], icon: "link", hint: "[]()", effect: .link),
        Spell(
            id: "callout", title: String(localized: "Callout"), subtitle: String(localized: "A note that stands out"),
            aliases: ["note", "alert", "tip", "warning", "admonition"], icon: "sparkles", hint: "[!NOTE]",
            effect: .callout),
        Spell(
            id: "date", title: String(localized: "Date"), subtitle: String(localized: "Today's date"),
            aliases: ["today", "now"], icon: "calendar", effect: .date),
        Spell(
            id: "frontmatter", title: String(localized: "Frontmatter"), subtitle: String(localized: "YAML properties"),
            aliases: ["yaml", "metadata", "properties"], icon: "list.bullet.rectangle", hint: "---",
            effect: .frontmatter),
    ]

    /// Spells matching `query`, best first. Recently cast spells rank above others that
    /// match as well, and lead the list when there's no query.
    public static func matching(_ query: String, in spells: [Spell] = standard, recent: [String] = []) -> [Spell] {
        let query = query.lowercased().trimmingCharacters(in: .whitespaces)
        struct Ranked {
            var spell: Spell
            var score: Int
            var recency: Int
            var order: Int
        }
        let ranked = spells.enumerated().compactMap { order, spell -> Ranked? in
            guard let score = score(spell, query) else { return nil }
            return Ranked(spell: spell, score: score, recency: recent.firstIndex(of: spell.id) ?? Int.max, order: order)
        }
        return ranked.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.recency != rhs.recency { return lhs.recency < rhs.recency }
            return lhs.order < rhs.order
        }.map(\.spell)
    }

    /// How well `spell` matches: exact names beat prefixes beat substrings beat letters in
    /// order (`hd2` finds Heading 2). Nil when it doesn't match.
    static func score(_ spell: Spell, _ query: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        let names = [spell.id, spell.title.lowercased()] + spell.aliases.map { $0.lowercased() }
        let compactTitle = spell.title.lowercased().replacingOccurrences(of: " ", with: "")
        if names.contains(query) || compactTitle == query { return 100 }
        if names.contains(where: { $0.hasPrefix(query) }) || compactTitle.hasPrefix(query) { return 80 }
        if names.contains(where: { $0.contains(query) }) { return 50 }
        if isSubsequence(query, of: compactTitle) || isSubsequence(query, of: spell.id) { return 20 }
        return nil
    }

    private static func isSubsequence(_ query: String, of text: String) -> Bool {
        var remaining = Substring(query)
        for character in text where remaining.first == character {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }

    /// Languages offered after the Code block spell.
    public static let languages = [
        "swift", "javascript", "typescript", "tsx", "python", "ruby", "go", "rust", "java", "kotlin", "c", "cpp",
        "csharp", "bash", "shell", "zsh", "json", "yaml", "toml", "html", "css", "scss", "sql", "markdown", "mdx",
        "diff", "dockerfile", "graphql", "lua", "php", "elixir", "haskell", "nix", "text",
    ]
}
