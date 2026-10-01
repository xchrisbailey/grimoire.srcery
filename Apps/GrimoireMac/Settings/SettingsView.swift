import GrimoireCore
import GrimoireEditor
import SwiftUI

/// The Settings window (⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Appearance", systemImage: "paintpalette") {
                AppearanceSettings()
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

    /// The editor's look from the chosen light and dark themes.
    var editorTheme: EditorTheme {
        EditorTheme(light: lightTheme, dark: darkTheme)
    }
}
