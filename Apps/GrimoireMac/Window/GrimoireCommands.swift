import AppKit
import GrimoireEditor
import SwiftUI

/// The File and View menu commands. Menu bar titles stay plain, per the brand voice.
struct GrimoireCommands: Commands {
    @FocusedValue(\.windowState) private var window
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New File") { window?.newFile() }
                .keyboardShortcut("n")
                .disabled(window?.folderForNewFiles == nil)
            Button("New Window") { openWindow(id: "project") }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("New Project…") { window?.projectPrompt = .new }
                .keyboardShortcut("n", modifiers: [.command, .control])
                .disabled(window == nil)
            Button("Add Folder…") { window?.bindFolders() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(window?.project == nil)
            Divider()
            Button("Open Quickly…") { window?.showPalette(.summon) }
                .keyboardShortcut("p")
                .disabled(window?.project == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find in Project…") { window?.search.begin(with: window?.editor.findQuery) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(window?.project == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
            Button("Save") { window?.save() }
                .keyboardShortcut("s")
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
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(window?.document == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy as Rich Text") { window?.copyAsRichText() }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                .disabled(window?.document == nil)
        }
        SidebarCommands()
        CommandGroup(after: .sidebar) {
            Toggle(
                "Raw Source",
                isOn: Binding(
                    get: { window?.editorMode == .raw },
                    set: { window?.editorMode = $0 ? .raw : .preview })
            )
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(window?.document == nil)
            Toggle(
                "Focus Mode",
                isOn: Binding(
                    get: { window?.focusMode == true },
                    set: { window?.setFocusMode($0) })
            )
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(window == nil)
            Divider()
            Button("Jump to Heading…") { window?.showPalette(.headings) }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                .disabled(window?.document == nil)
            Button("Incantations…") { window?.showPalette(.incantations) }
                .keyboardShortcut("k")
                .disabled(window == nil)
        }
    }
}
