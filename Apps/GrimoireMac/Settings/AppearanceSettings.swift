import GrimoireCore
import GrimoireEditor
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Appearance: light or dark, the theme for each, and themes borrowed from
/// VS Code.
struct AppearanceSettings: View {
    @State private var themes = ThemeLibrary.shared
    @State private var isDropTargeted = false
    @State private var importError: ImportFailure?
    @State private var removing: Theme?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Appearance", selection: Binding(get: { themes.appearance }, set: setAppearance)) {
                Text("Match System").tag(AppearanceMode.system)
                Text("Light").tag(AppearanceMode.light)
                Text("Dark").tag(AppearanceMode.dark)
            }
            .pickerStyle(.segmented)
            .fixedSize()

            HStack(alignment: .firstTextBaseline) {
                Text("Themes")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Borrow a look from VS Code…", action: chooseFile)
            }
            HStack(spacing: 16) {
                themePicker(String(localized: "Light"), selection: themes.lightThemeID, set: themes.setLightTheme)
                themePicker(String(localized: "Dark"), selection: themes.darkThemeID, set: themes.setDarkTheme)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(themes.themes) { theme in
                        ThemeRow(
                            theme: theme, isLight: theme.id == themes.lightTheme.id,
                            isDark: theme.id == themes.darkTheme.id,
                            useForLight: { themes.setLightTheme(theme.id) },
                            useForDark: { themes.setDarkTheme(theme.id) },
                            remove: { removing = theme })
                    }
                }
            }
            .frame(minHeight: 220, maxHeight: 320)

            dropZone

            Text(
                // swiftlint:disable:next line_length
                "Imported themes bring their editor and syntax colors. Semantic token colors aren't used, and anything a theme leaves out comes from Catppuccin."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .alert(
            importError?.title ?? "",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError?.message ?? "")
        }
        .confirmationDialog(
            String(localized: "Remove “\(removing?.name ?? "")”?"),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
        ) {
            Button("Remove Theme", role: .destructive) {
                if let removing { themes.remove(removing.id) }
            }
        } message: {
            Text("The theme is removed from Grimoire. The file it came from isn't touched.")
        }
    }

    private func themePicker(_ title: String, selection: String, set: @escaping @Sendable @MainActor (String) -> Void)
        -> some View
    {
        Picker(title, selection: Binding(get: { selection }, set: set)) {
            ForEach(themes.themes) { theme in
                Text(theme.name).tag(theme.id)
            }
        }
        .fixedSize()
    }

    private var dropZone: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle")
                .font(.title3)
                .foregroundStyle(Color.brand(\.magic))
            Text("Drop a VS Code theme here (.json or .vsix) to borrow its look.")
                .foregroundStyle(Color.brand(\.subtext))
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(isDropTargeted ? Color.brand(\.magic).opacity(0.1) : .clear, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTargeted ? Color.brand(\.magic) : Color.brand(\.surface1),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls { importThemes(from: url) }
            return !urls.isEmpty
        } isTargeted: {
            isDropTargeted = $0
        }
    }

    private func setAppearance(_ mode: AppearanceMode) {
        themes.setAppearance(mode)
        themes.applyAppearance()
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json] + ["vsix", "tmTheme"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Choose a VS Code theme (.json) or extension (.vsix).")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { importThemes(from: url) }
    }

    private func importThemes(from url: URL) {
        do {
            try themes.importThemes(from: url)
        } catch {
            importError = ImportFailure(
                title: String(localized: "Couldn't import “\(url.lastPathComponent)”."),
                message: error.localizedDescription)
        }
    }

    private struct ImportFailure {
        var title: String
        var message: String
    }
}

/// One theme: a strip of its colors, its name and where it came from, and which
/// appearance uses it.
private struct ThemeRow: View {
    let theme: Theme
    let isLight: Bool
    let isDark: Bool
    let useForLight: () -> Void
    let useForDark: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 0) {
                ForEach(Array(swatches.enumerated()), id: \.offset) { _, color in
                    Rectangle().fill(Color(color))
                }
            }
            .frame(width: 110, height: 26)
            .clipShape(.rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.brand(\.surface0)))

            VStack(alignment: .leading, spacing: 1) {
                Text(theme.name)
                    .brandFont(.chrome)
                    .foregroundStyle(Color.brand(\.ink))
                Text(origin)
                    .font(.caption)
                    .foregroundStyle(Color.brand(\.overlay1))
            }
            Spacer(minLength: 8)
            pill(String(localized: "Light"), isOn: isLight, action: useForLight)
            pill(String(localized: "Dark"), isOn: isDark, action: useForDark)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.brand(\.page), in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isLight || isDark ? Color.brand(\.magic) : Color.brand(\.surface0))
        )
        .contextMenu {
            Button("Use for Light", action: useForLight)
            Button("Use for Dark", action: useForDark)
            if case .imported = theme.origin {
                Divider()
                Button("Remove Theme…", role: .destructive, action: remove)
            }
        }
    }

    private var swatches: [PaletteColor] {
        let palette = theme.palette
        return [palette.page, palette.ink, palette.magic, palette.caret, palette.callout]
    }

    private var origin: String {
        switch theme.origin {
        case .builtIn: String(localized: "Built in")
        case .imported(let fileName): String(localized: "Imported from \(fileName)")
        }
    }

    private func pill(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.brand(.metadata))
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(isOn ? Color.brand(\.page) : Color.brand(\.subtext))
                .background(isOn ? Color.brand(\.magic) : Color.brand(\.surface0), in: .capsule)
        }
        .buttonStyle(.plain)
        .help(isOn ? Text("Used in \(title) mode") : Text("Use in \(title) mode"))
    }
}
