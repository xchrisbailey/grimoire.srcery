import GrimoireCore
import GrimoireEditor
import SwiftUI

/// The Settings window (⌘,). Every setting applies as soon as it changes.
struct SettingsView: View {
    @Environment(ProjectLibrary.self) private var library

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings()
            }
            Tab("Editor", systemImage: "character.cursor.ibeam") {
                EditorSettings()
            }
            Tab("Appearance", systemImage: "paintpalette") {
                AppearanceSettings()
            }
            Tab("Spelling", systemImage: "textformat.abc.dottedunderline") {
                SpellingSettings()
            }
            Tab("Intelligence", systemImage: "sparkles") {
                IntelligenceSettings()
            }
            Tab("Shortcuts", systemImage: "command") {
                ShortcutSettings()
            }
        }
        .frame(width: 600)
        .tint(Color.brand(\.magic))
        .alert(
            String(localized: "Project changes couldn’t be saved"),
            isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })
        ) {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([library.storageURL])
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your project changes were not saved. Check access to the projects file, then try the change again.")
            Text(library.lastError?.localizedDescription ?? "")
        }
    }
}

extension ProjectLibrary {
    /// Settings bindings cannot throw. Keep their displayed value in the committed
    /// snapshot and report failures in the Settings window instead of accepting the edit.
    @discardableResult
    func editProject(_ id: Project.ID, _ change: (inout Project) -> Void) -> Bool {
        do {
            try update(id, change)
            return true
        } catch {
            lastError = error
            return false
        }
    }
}

extension ThemeLibrary {
    /// Puts the app in light or dark mode, or lets it follow the system.
    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// The editor's look: the chosen light and dark themes, with the fonts and sizes from
    /// Settings › Appearance and the layout from Settings › Editor.
    func editorTheme(_ preferences: Preferences) -> EditorTheme {
        var theme = EditorTheme(light: lightTheme, dark: darkTheme)
        theme.bodySize = preferences.proseSize
        theme.codeSize = preferences.codeSize
        theme.proseFamily = preferences.proseFont
        theme.codeFamily = preferences.codeFont
        theme.setLineHeight(preferences.lineHeight)
        // Without the limit the column fills the window.
        theme.maxLineWidth = preferences.limitsLineWidth ? preferences.maxLineWidth : 100_000
        theme.tabWidth = preferences.tabWidth
        theme.partsOfSpeech = preferences.highlightsSyntax ? preferences.partsOfSpeech : []
        return theme
    }
}
