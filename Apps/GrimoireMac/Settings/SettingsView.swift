import GrimoireCore
import GrimoireEditor
import SwiftUI

/// The Settings window (⌘,). Every setting applies as soon as it changes.
struct SettingsView: View {
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
        theme.maxLineWidth = preferences.maxLineWidth
        return theme
    }
}
