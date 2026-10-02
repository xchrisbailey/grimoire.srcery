import Foundation

/// A key and the modifiers held with it, platform-neutral so Settings can save it and
/// each app can turn it into its own menu shortcut.
public struct KeyCombo: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// Keys that aren't a character, by name.
    public enum Named: String, CaseIterable, Sendable {
        case `return`, tab, space, delete, forwardDelete, escape, upArrow, downArrow, leftArrow, rightArrow
    }

    /// A lowercased character, or a `Named` key's raw value.
    public var key: String
    public var modifiers: Modifiers

    public init(_ key: String, _ modifiers: Modifiers = .command) {
        self.key = key.count == 1 ? key.lowercased() : key
        self.modifiers = modifiers
    }

    public init(_ key: Named, _ modifiers: Modifiers = .command) {
        self.init(key.rawValue, modifiers)
    }

    public var named: Named? { Named(rawValue: key) }

    /// Whether the combo can be a menu shortcut: it holds ⌘ or ⌃, so typing never
    /// triggers it.
    public var isMenuShortcut: Bool { !modifiers.isDisjoint(with: [.command, .control]) }

    /// How menus write it, like `⌥⇧⌘C`.
    public var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        switch named {
        case .return: text += "↩"
        case .tab: text += "⇥"
        case .space: text += "Space"
        case .delete: text += "⌫"
        case .forwardDelete: text += "⌦"
        case .escape: text += "esc"
        case .upArrow: text += "↑"
        case .downArrow: text += "↓"
        case .leftArrow: text += "←"
        case .rightArrow: text += "→"
        case nil: text += key.uppercased()
        }
        return text
    }
}

/// The commands whose shortcuts can be changed in Settings.
public enum ShortcutAction: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    case newFile, newWindow, newProject, addFolder, openQuickly, save, close, print
    case copyRichText, findInProject, askProject
    case rawSource, focusMode, jumpToHeading, incantations
    case toggleTask, duplicateBlock, writingTools

    public var defaultCombo: KeyCombo {
        switch self {
        case .newFile: KeyCombo("n")
        case .newWindow: KeyCombo("n", [.option, .command])
        case .newProject: KeyCombo("n", [.control, .command])
        case .addFolder: KeyCombo("o", [.shift, .command])
        case .openQuickly: KeyCombo("p")
        case .save: KeyCombo("s")
        case .close: KeyCombo("w")
        case .print: KeyCombo("p", [.option, .command])
        case .copyRichText: KeyCombo("c", [.option, .shift, .command])
        case .findInProject: KeyCombo("e", [.shift, .command])
        case .askProject: KeyCombo("a", [.shift, .command])
        case .rawSource: KeyCombo("r", [.shift, .command])
        case .focusMode: KeyCombo("f", [.shift, .command])
        case .jumpToHeading: KeyCombo("j", [.shift, .command])
        case .incantations: KeyCombo("k")
        case .toggleTask: KeyCombo(.return)
        case .duplicateBlock: KeyCombo("d", [.shift, .command])
        case .writingTools: KeyCombo("j", [.option, .command])
        }
    }
}

extension Preferences {
    /// Where the shortcut overrides are saved, for views that redraw when they change.
    public static let shortcutsKey = Key.shortcuts

    /// The shortcut for `action`: the user's choice, else the default. Nil when the user
    /// cleared it.
    public func shortcut(for action: ShortcutAction) -> KeyCombo? {
        guard let custom = shortcutOverrides[action] else { return action.defaultCombo }
        return custom.key.isEmpty ? nil : custom
    }

    /// Changes `action`'s shortcut; nil leaves it without one. Choosing the default again
    /// forgets the override.
    public func setShortcut(_ combo: KeyCombo?, for action: ShortcutAction) {
        if combo == action.defaultCombo {
            shortcutOverrides[action] = nil
        } else {
            shortcutOverrides[action] = combo ?? KeyCombo("", [])
        }
    }

    /// The other action already using `combo`, if any.
    public func action(using combo: KeyCombo, except action: ShortcutAction? = nil) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0 != action && shortcut(for: $0) == combo }
    }

    public func resetShortcuts() {
        shortcutOverrides = [:]
    }
}
