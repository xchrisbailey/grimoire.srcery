import GrimoireCore
import GrimoireEditor
import SwiftUI

/// iA Writer style syntax highlighting: words colored by part of speech, to spot
/// repetition, weak verbs and piles of adjectives.
struct SyntaxHighlightSettings: View {
    @Bindable var preferences: Preferences
    @State private var themes = ThemeLibrary.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Section {
            Toggle("Color words by part of speech", isOn: $preferences.highlightsSyntax)
            if preferences.highlightsSyntax {
                ForEach(PartOfSpeech.allCases, id: \.self) { part in
                    Toggle(isOn: binding(for: part)) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(swatch(for: part)))
                                .frame(width: 10, height: 10)
                            Text(title(for: part))
                        }
                    }
                }
            }
        } header: {
            Text("Syntax highlighting")
        } footer: {
            Text("Colors come from the theme. Code, links and headings keep their own.")
                .foregroundStyle(.secondary)
        }
    }

    private func binding(for part: PartOfSpeech) -> Binding<Bool> {
        Binding(
            get: { preferences.partsOfSpeech.contains(part) },
            set: { isOn in
                if isOn { preferences.partsOfSpeech.insert(part) } else { preferences.partsOfSpeech.remove(part) }
            })
    }

    private func swatch(for part: PartOfSpeech) -> PaletteColor {
        let palette = themes.theme(dark: colorScheme == .dark).palette
        switch part {
        case .adjective: return palette.caret
        case .noun: return palette.sparkle
        case .adverb: return palette.magic
        case .verb: return palette.link
        case .conjunction: return palette.string
        }
    }

    private func title(for part: PartOfSpeech) -> String {
        switch part {
        case .adjective: String(localized: "Adjectives")
        case .noun: String(localized: "Nouns")
        case .adverb: String(localized: "Adverbs")
        case .verb: String(localized: "Verbs")
        case .conjunction: String(localized: "Conjunctions")
        }
    }
}
