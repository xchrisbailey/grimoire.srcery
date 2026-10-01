import Foundation
import GrimoireCore
import SwiftTreeSitter
import TreeSitterBash
import TreeSitterC
import TreeSitterCPP
import TreeSitterCSS
import TreeSitterGo
import TreeSitterHTML
import TreeSitterJSON
import TreeSitterJavaScript
import TreeSitterMarkdown
import TreeSitterPython
import TreeSitterRuby
import TreeSitterRust
import TreeSitterSql
import TreeSitterSwift
import TreeSitterTOML
import TreeSitterTSX
import TreeSitterTypeScript
import TreeSitterYAML

/// One highlighted run of code: where it is (UTF-16, relative to the code) and what it is.
public struct CodeHighlight: Equatable, Sendable {
    public var range: NSRange
    public var token: CodeToken

    public init(range: NSRange, token: CodeToken) {
        self.range = range
        self.token = token
    }
}

/// Highlights code with tree-sitter grammars, by a fenced block's info string
/// (` ```swift `). Work happens on a background queue; results are cached by language and
/// text.
public final class CodeHighlighter: @unchecked Sendable {
    public static let shared = CodeHighlighter()

    private let queue = DispatchQueue(label: "computer.srcery.grimoire.highlighter", qos: .userInitiated)
    /// Loaded grammars and queries, by language. Only touched on `queue`.
    private var loaded: [Grammar: (parser: Parser, query: Query)?] = [:]

    public init() {}

    /// Whether there's a grammar for this info string.
    public static func supports(_ info: String?) -> Bool {
        Grammar(info: info) != nil
    }

    /// Highlights `code` on the background queue and calls `completion` there. An unknown
    /// language gives no highlights.
    public func highlight(_ code: String, language: String?, completion: @escaping @Sendable ([CodeHighlight]) -> Void)
    {
        queue.async { [self] in completion(highlightNow(code, language: language)) }
    }

    /// Highlights `code` on the caller's thread, waiting for any queued work first.
    public func highlightSync(_ code: String, language: String?) -> [CodeHighlight] {
        queue.sync { highlightNow(code, language: language) }
    }

    private func highlightNow(_ code: String, language: String?) -> [CodeHighlight] {
        guard let grammar = Grammar(info: language), let (parser, query) = load(grammar),
            let tree = parser.parse(code)
        else { return [] }
        let matches = query.execute(in: tree).resolve(with: .init(string: code))
        // Ordered from outer to inner, so inner, more specific captures win.
        return matches.highlights().compactMap { named in
            guard let token = Self.token(for: named.nameComponents), named.range.length > 0 else { return nil }
            return CodeHighlight(range: named.range, token: token)
        }
    }

    private func load(_ grammar: Grammar) -> (parser: Parser, query: Query)? {
        if let cached = loaded[grammar] { return cached }
        var result: (Parser, Query)?
        let language = Language(language: grammar.language)
        let parser = Parser()
        let source = grammar.queryBundles.compactMap(Self.highlightsQuery).joined(separator: "\n")
        if (try? parser.setLanguage(language)) != nil, !source.isEmpty,
            let query = try? Query(language: language, data: Data(source.utf8))
        {
            result = (parser, query)
        }
        loaded[grammar] = result
        return result
    }

    /// A grammar package's `highlights.scm`, wherever its resource bundle was copied: next
    /// to the app's resources, or next to the test bundle.
    private static func highlightsQuery(bundleName: String) -> String? {
        let folders = [
            Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle(for: CodeHighlighter.self).resourceURL,
            Bundle(for: CodeHighlighter.self).bundleURL.deletingLastPathComponent(),
        ].compactMap { $0 }
        for folder in folders {
            let bundle = folder.appending(path: bundleName + ".bundle")
            for path in ["Contents/Resources/queries/highlights.scm", "queries/highlights.scm"] {
                if let source = try? String(contentsOf: bundle.appending(path: path), encoding: .utf8) {
                    return source
                }
            }
        }
        return nil
    }

    // MARK: - Capture names

    /// The theme token for a capture like `function.method.builtin`: the most specific
    /// name tree-sitter grammars commonly use.
    static func token(for components: [String]) -> CodeToken? {
        guard let first = components.first else { return nil }
        let name = components.joined(separator: ".")
        if let exact = specific[name] { return exact }
        if components.count > 1, let pair = specific[components[0] + "." + components[1]] { return pair }
        return general[first]
    }

    private static let specific: [String: CodeToken] = [
        "string.escape": .escape, "string.special.key": .property, "string.special.symbol": .constant,
        "string.regexp": .escape, "function.builtin": .builtin, "variable.builtin": .builtin,
        "variable.parameter": .variable, "variable.member": .property, "constant.builtin": .constant,
        "type.builtin": .type, "tag.attribute": .attribute, "keyword.operator": .operator,
        "text.title": .keyword, "text.literal": .string, "text.uri": .function, "text.reference": .function,
        "punctuation.special": .punctuation, "comment.documentation": .comment,
    ]

    private static let general: [String: CodeToken] = [
        "keyword": .keyword, "include": .keyword, "conditional": .keyword, "repeat": .keyword,
        "exception": .keyword, "storageclass": .keyword, "preproc": .keyword, "define": .keyword,
        "string": .string, "character": .string, "comment": .comment, "function": .function, "method": .function,
        "constructor": .type, "type": .type, "class": .type, "namespace": .type, "module": .type,
        "number": .number, "float": .number, "boolean": .constant, "constant": .constant, "variable": .variable,
        "property": .property, "field": .property, "label": .property, "attribute": .attribute,
        "operator": .operator, "punctuation": .punctuation, "delimiter": .punctuation, "tag": .tag,
        "escape": .escape, "embedded": .variable,
    ]
}

/// The grammars Grimoire bundles, and the info strings that pick them.
enum Grammar: Hashable, CaseIterable {
    case swift, javascript, typescript, tsx, python, go, rust, json, bash, html, css, c, cpp, ruby, yaml, toml
    case markdown, sql

    init?(info: String?) {
        guard let info else { return nil }
        let word = info.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        let name = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "{}."))
        guard let grammar = Self.aliases[name] else { return nil }
        self = grammar
    }

    static let aliases: [String: Grammar] = [
        "swift": .swift, "javascript": .javascript, "js": .javascript, "jsx": .javascript, "mjs": .javascript,
        "cjs": .javascript, "typescript": .typescript, "ts": .typescript, "tsx": .tsx, "python": .python,
        "py": .python, "go": .go, "golang": .go, "rust": .rust, "rs": .rust, "json": .json, "jsonc": .json,
        "json5": .json, "bash": .bash, "sh": .bash, "shell": .bash, "zsh": .bash, "console": .bash, "html": .html,
        "htm": .html, "xml": .html, "svg": .html, "css": .css, "c": .c, "h": .c, "cpp": .cpp, "c++": .cpp, "cc": .cpp,
        "cxx": .cpp, "hpp": .cpp, "objc": .c, "ruby": .ruby, "rb": .ruby, "yaml": .yaml, "yml": .yaml, "toml": .toml,
        "markdown": .markdown, "md": .markdown, "sql": .sql,
    ]

    var language: OpaquePointer {
        switch self {
        case .swift: tree_sitter_swift()
        case .javascript: tree_sitter_javascript()
        case .typescript: tree_sitter_typescript()
        case .tsx: tree_sitter_tsx()
        case .python: tree_sitter_python()
        case .go: tree_sitter_go()
        case .rust: tree_sitter_rust()
        case .json: tree_sitter_json()
        case .bash: tree_sitter_bash()
        case .html: tree_sitter_html()
        case .css: tree_sitter_css()
        case .c: tree_sitter_c()
        case .cpp: tree_sitter_cpp()
        case .ruby: tree_sitter_ruby()
        case .yaml: tree_sitter_yaml()
        case .toml: tree_sitter_toml()
        case .markdown: tree_sitter_markdown()
        case .sql: tree_sitter_sql()
        }
    }

    /// The resource bundles whose `highlights.scm` make up this grammar's query.
    /// TypeScript and C++ build on JavaScript's and C's, as editors do.
    var queryBundles: [String] {
        switch self {
        case .swift: ["TreeSitterSwift_TreeSitterSwift"]
        case .javascript: ["TreeSitterJavaScript_TreeSitterJavaScript"]
        case .typescript, .tsx:
            ["TreeSitterJavaScript_TreeSitterJavaScript", "TreeSitterTypeScript_TreeSitterTypeScript"]
        case .python: ["TreeSitterPython_TreeSitterPython"]
        case .go: ["TreeSitterGo_TreeSitterGo"]
        case .rust: ["TreeSitterRust_TreeSitterRust"]
        case .json: ["TreeSitterJSON_TreeSitterJSON"]
        case .bash: ["TreeSitterBash_TreeSitterBash"]
        case .html: ["TreeSitterHTML_TreeSitterHTML"]
        case .css: ["TreeSitterCSS_TreeSitterCSS"]
        case .c: ["TreeSitterC_TreeSitterC"]
        case .cpp: ["TreeSitterC_TreeSitterC", "TreeSitterCPP_TreeSitterCPP"]
        case .ruby: ["TreeSitterRuby_TreeSitterRuby"]
        case .yaml: ["TreeSitterYAML_TreeSitterYAML"]
        case .toml: ["TreeSitterTOML_TreeSitterTOML"]
        case .markdown: ["TreeSitterMarkdown_TreeSitterMarkdown"]
        case .sql: ["TreeSitterSql_TreeSitterSql"]
        }
    }
}
