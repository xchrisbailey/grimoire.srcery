import Foundation

/// A VS Code color theme, read from its JSON (comments and trailing commas allowed) with
/// any `include`d parent merged in, ready to become a `Theme`.
///
/// Known limits: a parent theme is found only in the same `.vsix` or folder,
/// `semanticTokenColors` are ignored (there's no language server), and anything the theme
/// leaves out comes from Catppuccin Mocha or Latte.
public struct VSCodeTheme {
    public var name: String
    /// `dark`, `light`, `hc` or `hcLight`, when the theme says.
    public var type: String?
    public var colors: [String: String]
    var rules: TextMateRules

    /// Reads a theme file. `load` fetches files it refers to (`include`, a `.tmTheme`), by
    /// path relative to the file being read; return nil when one can't be found.
    public init(data: Data, fallbackName: String, load: (String) -> Data? = { _ in nil }) throws {
        try self.init(data: data, fallbackName: fallbackName, load: load, depth: 0)
    }

    private init(data: Data, fallbackName: String, load: (String) -> Data?, depth: Int) throws {
        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            plist["settings"] != nil
        {
            self.init(textMate: plist, fallbackName: fallbackName)
            return
        }
        guard let json = try LenientJSON.parse(data) as? [String: Any] else { throw ThemeImportError.notATheme }
        var colors: [String: String] = [:]
        var tokenEntries: [[String: Any]] = []
        var type = json["type"] as? String
        var name = json["name"] as? String

        // A parent theme's settings come first, so this theme's own override them.
        if let include = json["include"] as? String, depth < 8, let parentData = load(include) {
            let folder = (include as NSString).deletingLastPathComponent
            let parent = try VSCodeTheme(
                data: parentData, fallbackName: fallbackName,
                load: { load(folder.isEmpty ? $0 : (folder as NSString).appendingPathComponent($0)) }, depth: depth + 1)
            colors = parent.colors
            tokenEntries = parent.rules.entries
            type = type ?? parent.type
            name = name ?? parent.name
        }
        for (key, value) in json["colors"] as? [String: Any] ?? [:] {
            if let value = value as? String { colors[key] = value }
        }
        if let entries = json["tokenColors"] as? [[String: Any]] {
            tokenEntries += entries
        } else if let path = json["tokenColors"] as? String, let data = load(path),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        {
            let textMate = VSCodeTheme(textMate: plist, fallbackName: fallbackName)
            tokenEntries += textMate.rules.entries
            colors.merge(textMate.colors) { mine, _ in mine }
        }
        self.init(name: name ?? fallbackName, type: type, colors: colors, entries: tokenEntries)
    }

    private init(name: String, type: String?, colors: [String: String], entries: [[String: Any]]) {
        self.name = name
        self.type = type
        self.colors = colors
        rules = TextMateRules(entries)
    }

    /// A TextMate `.tmTheme`: a settings array whose first, scope-less entry holds the editor colors.
    private init(textMate plist: [String: Any], fallbackName: String) {
        let settings = plist["settings"] as? [[String: Any]] ?? []
        var colors: [String: String] = [:]
        if let global = settings.first(where: { $0["scope"] == nil })?["settings"] as? [String: String] {
            let keys = [
                "background": "editor.background", "foreground": "editor.foreground",
                "caret": "editorCursor.foreground", "selection": "editor.selectionBackground",
                "lineHighlight": "editor.lineHighlightBackground",
            ]
            for (from, to) in keys { colors[to] = global[from] }
        }
        self.init(name: plist["name"] as? String ?? fallbackName, type: nil, colors: colors, entries: settings)
    }

    /// Whether the theme is dark: what the extension declared (VS Code goes by that), else
    /// how dark its editor background is, else its `type`.
    public func isDark(hint: Bool? = nil) -> Bool {
        if let hint { return hint }
        if let background = colors["editor.background"].flatMap({ PaletteColor(hex: $0) }) {
            return background.luminance < 0.4
        }
        switch type?.lowercased() {
        case "light", "hclight", "vs", "hc-light": return false
        default: return true
        }
    }
}

/// Why a theme couldn't be imported. Errors stay plain, per the brand voice.
public enum ThemeImportError: LocalizedError, Equatable {
    case notATheme
    case noThemesInExtension
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .notATheme:
            String(localized: "This file isn't a VS Code color theme.")
        case .noThemesInExtension:
            String(localized: "This extension doesn't contain any color themes.")
        case .unreadable(let name):
            String(localized: "Couldn't read “\(name)”.")
        }
    }
}

/// JSON with comments and trailing commas, as VS Code writes it.
enum LenientJSON {
    static func parse(_ data: Data) throws -> Any {
        if let strict = try? JSONSerialization.jsonObject(with: data) { return strict }
        let cleaned = clean(Array(data))
        do {
            return try JSONSerialization.jsonObject(with: Data(cleaned))
        } catch {
            throw ThemeImportError.notATheme
        }
    }

    /// Drops `//` and `/* */` comments and commas before `}` or `]`, leaving strings alone.
    static func clean(_ bytes: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == quote {
                let end = endOfString(in: bytes, at: index)
                output += bytes[index..<end]
                index = end
            } else if let end = endOfComment(in: bytes, at: index) {
                index = end
            } else {
                let following = byte == comma ? nextSignificant(in: bytes, after: index) : nil
                if following != closeBrace, following != closeBracket { output.append(byte) }
                index += 1
            }
        }
        return output
    }

    private static let quote = UInt8(ascii: "\""), comma = UInt8(ascii: ",")
    private static let closeBrace = UInt8(ascii: "}"), closeBracket = UInt8(ascii: "]")
    private static let slash = UInt8(ascii: "/"), star = UInt8(ascii: "*"), backslash = UInt8(ascii: "\\")

    /// Where the string starting at `start` ends, just past its closing quote.
    private static func endOfString(in bytes: [UInt8], at start: Int) -> Int {
        var index = start + 1
        while index < bytes.count, bytes[index] != quote {
            index += bytes[index] == backslash ? 2 : 1
        }
        return min(index + 1, bytes.count)
    }

    /// Where the comment starting at `start` ends, or nil when no comment starts there.
    private static func endOfComment(in bytes: [UInt8], at start: Int) -> Int? {
        guard bytes[start] == slash, start + 1 < bytes.count else { return nil }
        var index = start + 2
        if bytes[start + 1] == slash {
            while index < bytes.count, bytes[index] != UInt8(ascii: "\n") { index += 1 }
            return index
        }
        guard bytes[start + 1] == star else { return nil }
        while index + 1 < bytes.count, !(bytes[index] == star && bytes[index + 1] == slash) { index += 1 }
        return min(index + 2, bytes.count)
    }

    /// The next byte after `index` that isn't whitespace or inside a comment.
    private static func nextSignificant(in bytes: [UInt8], after index: Int) -> UInt8? {
        var next = index + 1
        while next < bytes.count {
            if [9, 10, 13, 32].contains(bytes[next]) {
                next += 1
            } else if let end = endOfComment(in: bytes, at: next) {
                next = end
            } else {
                return bytes[next]
            }
        }
        return nil
    }
}
