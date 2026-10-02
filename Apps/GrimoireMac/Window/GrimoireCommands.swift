import AppKit
import GrimoireCore
import GrimoireEditor
import GrimoireIntelligence
import SwiftUI

/// The File and View menu commands. Menu bar titles stay plain, per the brand voice.
/// Their shortcuts come from Settings › Shortcuts.
struct GrimoireCommands: Commands {
    @FocusedValue(\.windowState) private var window
    @Environment(\.openWindow) private var openWindow
    /// Redraws the menus when a shortcut changes.
    @AppStorage(Preferences.shortcutsKey) private var shortcutOverrides = Data()

    private func shortcut(_ action: ShortcutAction) -> KeyboardShortcut? {
        Preferences.shared.shortcut(for: action)?.keyboardShortcut
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New File") { window?.newFile() }
                .keyboardShortcut(shortcut(.newFile))
                .disabled(window?.folderForNewFiles == nil)
            Button("New Window") { openWindow(id: "project") }
                .keyboardShortcut(shortcut(.newWindow))
            Divider()
            Button("New Project…") { window?.projectPrompt = .new }
                .keyboardShortcut(shortcut(.newProject))
                .disabled(window == nil)
            Button("Add Folder…") { window?.bindFolders() }
                .keyboardShortcut(shortcut(.addFolder))
                .disabled(window?.project == nil)
            Divider()
            Button("Open Quickly…") { window?.showPalette(.summon) }
                .keyboardShortcut(shortcut(.openQuickly))
                .disabled(window?.project == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find in Project…") { window?.search.begin(with: window?.editor.findQuery) }
                .keyboardShortcut(shortcut(.findInProject))
                .disabled(window?.project == nil)
            Button("Ask Your Project…") { window?.showAsk() }
                .keyboardShortcut(shortcut(.askProject))
                .disabled(window.map { !IntelligenceService.shared.isAvailable(for: $0.project) } ?? true)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut(shortcut(.close))
            Button("Save") { window?.save() }
                .keyboardShortcut(shortcut(.save))
                .disabled(window?.document == nil)
            Button("Browse Versions…") { window?.showsVersions = true }
                .disabled(window?.document == nil)
            Divider()
            Button("Export as HTML…") { window?.exportHTML() }
                .disabled(window?.document == nil)
            Button("Export as PDF…") { window?.exportPDF() }
                .disabled(window?.document == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { window?.printDocument() }
                .keyboardShortcut(shortcut(.print))
                .disabled(window?.document == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy as Rich Text") { window?.copyAsRichText() }
                .keyboardShortcut(shortcut(.copyRichText))
                .disabled(window?.document == nil)
            Button("Paste Image as Markdown…") { window?.pasteImageAsMarkdown() }
                .disabled(window?.intelligenceReady != true)
        }
        SidebarCommands()
        CommandGroup(after: .sidebar) {
            Toggle(
                "Raw Source",
                isOn: Binding(
                    get: { window?.editorMode == .raw },
                    set: { window?.editorMode = $0 ? .raw : .preview })
            )
            .keyboardShortcut(shortcut(.rawSource))
            .disabled(window?.document == nil)
            Toggle(
                "Focus Mode",
                isOn: Binding(
                    get: { window?.focusMode == true },
                    set: { window?.setFocusMode($0) })
            )
            .keyboardShortcut(shortcut(.focusMode))
            .disabled(window == nil)
            Divider()
            Button("Jump to Heading…") { window?.showPalette(.headings) }
                .keyboardShortcut(shortcut(.jumpToHeading))
                .disabled(window?.document == nil)
            Button("Incantations…") { window?.showPalette(.incantations) }
                .keyboardShortcut(shortcut(.incantations))
                .disabled(window == nil)
        }
    }
}

extension KeyCombo {
    /// The combo as a SwiftUI menu shortcut.
    var keyboardShortcut: KeyboardShortcut {
        var modifiers: EventModifiers = []
        if self.modifiers.contains(.control) { modifiers.insert(.control) }
        if self.modifiers.contains(.option) { modifiers.insert(.option) }
        if self.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if self.modifiers.contains(.command) { modifiers.insert(.command) }
        return KeyboardShortcut(keyEquivalent, modifiers: modifiers)
    }

    private var keyEquivalent: KeyEquivalent {
        switch named {
        case .return: .return
        case .tab: .tab
        case .space: .space
        case .delete: .delete
        case .forwardDelete: .deleteForward
        case .escape: .escape
        case .upArrow: .upArrow
        case .downArrow: .downArrow
        case .leftArrow: .leftArrow
        case .rightArrow: .rightArrow
        case nil: KeyEquivalent(key.first ?? " ")
        }
    }
}
