import Foundation
import Observation

/// Whether the app follows the system's light or dark appearance or stays in one.
public enum AppearanceMode: String, CaseIterable, Sendable {
    case system, light, dark
}

/// The built-in and imported themes, and which one is used for light and for dark.
///
/// Imported themes are saved as JSON in `Application Support/<bundle id>/Themes`. Nothing
/// is written next to the file they came from.
@MainActor @Observable
public final class ThemeLibrary {
    /// The app's library. Views that read colors from it redraw when the themes change.
    public static let shared = ThemeLibrary()

    public private(set) var imported: [Theme] = []
    public private(set) var lightThemeID: String
    public private(set) var darkThemeID: String
    public private(set) var appearance: AppearanceMode
    /// The last import or save failure, for the UI to show.
    public var lastError: Error?

    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let light = "theme.light"
        static let dark = "theme.dark"
        static let appearance = "theme.appearance"
    }

    public init(folder: URL? = nil, defaults: UserDefaults = .standard) {
        let bundle = Bundle.main.bundleIdentifier ?? "computer.srcery.grimoire"
        self.folder =
            folder
            ?? URL.applicationSupportDirectory.appending(path: bundle, directoryHint: .isDirectory)
            .appending(path: "Themes", directoryHint: .isDirectory)
        self.defaults = defaults
        lightThemeID = defaults.string(forKey: Key.light) ?? Theme.latte.id
        darkThemeID = defaults.string(forKey: Key.dark) ?? Theme.mocha.id
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppearanceMode.init) ?? .system
        imported = loadImported()
    }

    /// Built-in themes first, then imported ones by name.
    public var themes: [Theme] { Theme.builtIn + imported }

    public func theme(_ id: String) -> Theme? {
        themes.first { $0.id == id }
    }

    /// The theme used in light mode, falling back to Latte if it was removed.
    public var lightTheme: Theme { theme(lightThemeID) ?? .latte }
    /// The theme used in dark mode, falling back to Mocha if it was removed.
    public var darkTheme: Theme { theme(darkThemeID) ?? .mocha }

    public func theme(dark: Bool) -> Theme { dark ? darkTheme : lightTheme }

    public func setLightTheme(_ id: String) {
        lightThemeID = id
        defaults.set(id, forKey: Key.light)
    }

    public func setDarkTheme(_ id: String) {
        darkThemeID = id
        defaults.set(id, forKey: Key.dark)
    }

    public func setAppearance(_ mode: AppearanceMode) {
        appearance = mode
        defaults.set(mode.rawValue, forKey: Key.appearance)
    }

    /// Imports the themes in a VS Code `.json` or `.vsix` file and saves them. A theme
    /// imported again from the same file replaces the earlier copy. The first theme goes
    /// into the slot matching its appearance, so the import shows at once.
    @discardableResult
    public func importThemes(from url: URL) throws -> [Theme] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let themes = try ThemeImport.themes(from: url)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var added: [Theme] = []
        for var theme in themes {
            if let existing = imported.first(where: { $0.name == theme.name && $0.origin == theme.origin }) {
                theme.id = existing.id
            }
            try save(theme)
            imported.removeAll { $0.id == theme.id }
            imported.append(theme)
            added.append(theme)
        }
        imported.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let first = added.first {
            if first.isDark { setDarkTheme(first.id) } else { setLightTheme(first.id) }
        }
        return added
    }

    /// Removes an imported theme. Built-in themes can't be removed.
    public func remove(_ id: String) {
        guard imported.contains(where: { $0.id == id }) else { return }
        imported.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: file(for: id))
        if lightThemeID == id { setLightTheme(Theme.latte.id) }
        if darkThemeID == id { setDarkTheme(Theme.mocha.id) }
    }

    // MARK: - Storage

    private func file(for id: String) -> URL {
        folder.appending(path: id + ".json")
    }

    private func save(_ theme: Theme) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(theme).write(to: file(for: theme.id), options: .atomic)
    }

    private func loadImported() -> [Theme] {
        let files =
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        return
            files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Theme.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
