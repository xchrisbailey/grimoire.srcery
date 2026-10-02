import AppKit
import GrimoireCore
import GrimoireEditor
import SwiftUI

/// Settings › Shortcuts: click a menu command's shortcut to record a new one. Shortcuts
/// that belong to macOS or to typing are listed but fixed.
struct ShortcutSettings: View {
    @State private var preferences = Preferences.shared
    @State private var recording: ShortcutAction?
    @State private var problem: String?

    var body: some View {
        Form {
            ForEach(Shortcut.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.shortcuts, id: \.title) { shortcut in
                        LabeledContent(shortcut.title) {
                            if let action = shortcut.action {
                                ShortcutRecorder(
                                    action: action, combo: preferences.shortcut(for: action),
                                    isRecording: recording == action,
                                    begin: { begin(action) }, finish: { finish(action, with: $0) })
                            } else {
                                Text(shortcut.keys)
                                    .font(.brand(.metadata))
                                    .foregroundStyle(Color.brand(\.subtext))
                            }
                        }
                    }
                }
            }
            Section {
                Button("Restore Default Shortcuts") {
                    recording = nil
                    problem = nil
                    preferences.resetShortcuts()
                }
                .disabled(preferences.shortcutOverrides.isEmpty)
            } footer: {
                Text(problem ?? String(localized: "While recording, Delete removes the shortcut and Escape cancels."))
                    .foregroundStyle(problem == nil ? Color.secondary : Color.brand(\.error))
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 480)
        .onDisappear { recording = nil }
    }

    private func begin(_ action: ShortcutAction) {
        problem = nil
        recording = recording == action ? nil : action
    }

    /// Takes the recorder's result: `.cancel` changes nothing, `.clear` removes the
    /// shortcut, and a combo replaces it unless something else already uses it.
    private func finish(_ action: ShortcutAction, with result: ShortcutRecorder.Result) {
        recording = nil
        switch result {
        case .cancel:
            problem = nil
        case .clear:
            problem = nil
            preferences.setShortcut(nil, for: action)
        case .combo(let combo):
            if !combo.isMenuShortcut {
                problem = String(localized: "Shortcuts need ⌘ or ⌃, so typing never sets them off.")
            } else if let other = preferences.action(using: combo, except: action) {
                problem = String(localized: "\(combo.display) is already used for \(other.title).")
            } else if let fixed = Shortcut.fixedTitle(for: combo) {
                problem = String(localized: "\(combo.display) is already used for \(fixed).")
            } else {
                problem = nil
                preferences.setShortcut(combo, for: action)
            }
        }
    }
}

/// The current shortcut as a button; clicked, it waits for the next key press.
private struct ShortcutRecorder: View {
    enum Result {
        case cancel, clear
        case combo(KeyCombo)
    }

    let action: ShortcutAction
    let combo: KeyCombo?
    let isRecording: Bool
    let begin: () -> Void
    let finish: (Result) -> Void
    @State private var monitor: Any?

    var body: some View {
        Button(action: begin) {
            Text(label)
                .font(.brand(.metadata))
                .foregroundStyle(isRecording ? Color.brand(\.magic) : Color.brand(\.ink))
                .frame(minWidth: 72)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.brand(\.surface0), in: .rect(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isRecording ? Color.brand(\.magic) : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(Text("Click, then press the new shortcut"))
        .accessibilityLabel(Text("\(action.title) shortcut"))
        .accessibilityValue(Text(combo?.display ?? String(localized: "None")))
        .onChange(of: isRecording, initial: true) { _, isOn in isOn ? startMonitoring() : stopMonitoring() }
        .onDisappear(perform: stopMonitoring)
        .contextMenu {
            if combo != action.defaultCombo {
                Button("Use Default (\(action.defaultCombo.display))") {
                    finish(.combo(action.defaultCombo))
                }
            }
            if combo != nil {
                Button("Remove Shortcut") { finish(.clear) }
            }
        }
    }

    private var label: String {
        if isRecording { return String(localized: "Type shortcut…") }
        return combo?.display ?? String(localized: "None")
    }

    private func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let combo = KeyCombo(event: event)
            if combo == KeyCombo(.escape, []) {
                finish(.cancel)
            } else if combo == KeyCombo(.delete, []) || combo == KeyCombo(.forwardDelete, []) {
                finish(.clear)
            } else if let combo {
                finish(.combo(combo))
            }
            return nil
        }
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension ShortcutAction {
    /// The command's name, as its menu item or Settings writes it.
    var title: String {
        switch self {
        case .newFile: String(localized: "New File")
        case .newWindow: String(localized: "New Window")
        case .newProject: String(localized: "New Project…")
        case .addFolder: String(localized: "Add Folder…")
        case .openQuickly: String(localized: "Open Quickly…")
        case .save: String(localized: "Save")
        case .close: String(localized: "Close")
        case .print: String(localized: "Print…")
        case .copyRichText: String(localized: "Copy as Rich Text")
        case .findInProject: String(localized: "Find in Project…")
        case .askProject: String(localized: "Ask Your Project…")
        case .rawSource: String(localized: "Raw Source")
        case .focusMode: String(localized: "Focus Mode")
        case .jumpToHeading: String(localized: "Jump to Heading…")
        case .incantations: String(localized: "Incantations…")
        case .toggleTask: String(localized: "Toggle Task")
        case .duplicateBlock: String(localized: "Duplicate Block")
        case .writingTools: String(localized: "Rewrite, shorten or expand the selection")
        }
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
    /// Set for shortcuts Settings can change.
    var action: ShortcutAction?

    init(_ title: String, _ keys: String) {
        self.title = title
        self.keys = keys
    }

    init(_ action: ShortcutAction) {
        self.title = action.title
        self.keys = action.defaultCombo.display
        self.action = action
    }

    /// Fixed shortcuts a recorded one mustn't take, with what they do.
    static func fixedTitle(for combo: KeyCombo) -> String? {
        let reserved: [(KeyCombo, String)] = [
            (KeyCombo("q"), String(localized: "Quit Grimoire")), (KeyCombo("h"), String(localized: "Hide Grimoire")),
            (KeyCombo("m"), String(localized: "Minimize")), (KeyCombo(","), String(localized: "Settings…")),
            (KeyCombo("z"), String(localized: "Undo")), (KeyCombo("z", [.shift, .command]), String(localized: "Redo")),
            (KeyCombo("x"), String(localized: "Cut")), (KeyCombo("c"), String(localized: "Copy")),
            (KeyCombo("v"), String(localized: "Paste")), (KeyCombo("a"), String(localized: "Select All")),
            (KeyCombo("s", [.control, .command]), String(localized: "Toggle Sidebar")),
        ]
        if let match = reserved.first(where: { $0.0 == combo }) { return match.1 }
        return groups.flatMap(\.shortcuts).first { $0.action == nil && $0.keys == combo.display }?.title
    }

    static let groups: [Group] = [
        Group(
            title: String(localized: "File"),
            shortcuts: [
                Shortcut(.newFile),
                Shortcut(.newWindow),
                Shortcut(.newProject),
                Shortcut(.addFolder),
                Shortcut(.save),
                Shortcut(.close),
                Shortcut(.print),
                Shortcut(.copyRichText),
            ]),
        Group(
            title: String(localized: "View"),
            shortcuts: [
                Shortcut(String(localized: "Toggle Sidebar"), "⌃⌘S"),
                Shortcut(.rawSource),
                Shortcut(.focusMode),
                Shortcut(String(localized: "Settings…"), "⌘,"),
            ]),
        Group(
            title: String(localized: "Find and go"),
            shortcuts: [
                Shortcut(String(localized: "Find…"), "⌘F"),
                Shortcut(String(localized: "Find and Replace…"), "⌥⌘F"),
                Shortcut(String(localized: "Find Next"), "⌘G"),
                Shortcut(String(localized: "Find Previous"), "⇧⌘G"),
                Shortcut(String(localized: "Use Selection for Find"), "⌘E"),
                Shortcut(.findInProject),
                Shortcut(.openQuickly),
                Shortcut(.jumpToHeading),
                Shortcut(.incantations),
            ]),
        Group(
            title: String(localized: "Intelligence"),
            shortcuts: [
                Shortcut(.askProject),
                Shortcut(.writingTools),
                Shortcut(String(localized: "Keep a response"), "↩"),
                Shortcut(String(localized: "Stop or discard a response"), "esc"),
            ]),
        Group(
            title: String(localized: "Blocks"),
            shortcuts: [
                Shortcut(String(localized: "Spells"), "/"),
                Shortcut(String(localized: "Line break in a block"), "⇧↩"),
                Shortcut(String(localized: "Indent or outdent a list item"), "⇥  ⇧⇥"),
                Shortcut(String(localized: "Move Block"), "⌥⇧↑  ⌥⇧↓"),
                Shortcut(.duplicateBlock),
                Shortcut(.toggleTask),
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
