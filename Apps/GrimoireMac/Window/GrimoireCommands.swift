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
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
            Button("Save") { window?.save() }
                .keyboardShortcut("s")
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
        }
    }
}
