import GrimoireEditor
import SwiftUI

/// Settings › Shortcuts: every keyboard shortcut, read-only for now.
struct ShortcutSettings: View {
    var body: some View {
        Form {
            ForEach(Shortcut.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.shortcuts, id: \.title) { shortcut in
                        LabeledContent(shortcut.title) {
                            Text(shortcut.keys)
                                .font(.brand(.metadata))
                                .foregroundStyle(Color.brand(\.subtext))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 480)
    }
}

/// A shortcut as Settings lists it.
struct Shortcut {
    struct Group {
        var title: String
        var shortcuts: [Shortcut]
    }

    var title: String
    var keys: String

    init(_ title: String, _ keys: String) {
        self.title = title
        self.keys = keys
    }

    static let groups: [Group] = [
        Group(
            title: String(localized: "File"),
            shortcuts: [
                Shortcut(String(localized: "New File"), "⌘N"),
                Shortcut(String(localized: "New Window"), "⌥⌘N"),
                Shortcut(String(localized: "New Project…"), "⌃⌘N"),
                Shortcut(String(localized: "Add Folder…"), "⇧⌘O"),
                Shortcut(String(localized: "Save"), "⌘S"),
                Shortcut(String(localized: "Close"), "⌘W"),
            ]),
        Group(
            title: String(localized: "View"),
            shortcuts: [
                Shortcut(String(localized: "Toggle Sidebar"), "⌃⌘S"),
                Shortcut(String(localized: "Raw Source"), "⇧⌘R"),
                Shortcut(String(localized: "Focus Mode"), "⇧⌘F"),
                Shortcut(String(localized: "Settings…"), "⌘,"),
            ]),
        Group(
            title: String(localized: "Blocks"),
            shortcuts: [
                Shortcut(String(localized: "Spells"), "/"),
                Shortcut(String(localized: "Line break in a block"), "⇧↩"),
                Shortcut(String(localized: "Indent or outdent a list item"), "⇥  ⇧⇥"),
                Shortcut(String(localized: "Move Block"), "⌥⇧↑  ⌥⇧↓"),
                Shortcut(String(localized: "Duplicate Block"), "⇧⌘D"),
                Shortcut(String(localized: "Toggle Task"), "⌘↩"),
                Shortcut(String(localized: "Select the block"), "esc"),
                Shortcut(String(localized: "Open a link"), "⌘-click"),
            ]),
        Group(
            title: String(localized: "Tables"),
            shortcuts: [
                Shortcut(String(localized: "Next Cell"), "⇥"),
                Shortcut(String(localized: "Previous Cell"), "⇧⇥"),
                Shortcut(String(localized: "Next Row"), "↩"),
            ]),
    ]
}
