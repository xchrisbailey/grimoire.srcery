import AppKit
import GrimoireCore
import GrimoireEditor
import SwiftUI

/// Settings › Editor: fonts, sizes, line height and width, and how the page behaves.
struct EditorSettings: View {
    @State private var preferences = Preferences.shared

    var body: some View {
        Form {
            Section {
                FontPicker(
                    title: String(localized: "Prose font"), family: $preferences.proseFont,
                    brandFamily: Preferences.defaultProseFont, monospacedOnly: false)
                Stepper(value: $preferences.proseSize, in: 11...28, step: 0.5) {
                    LabeledContent("Prose size", value: points(preferences.proseSize))
                }
                FontPicker(
                    title: String(localized: "Code font"), family: $preferences.codeFont,
                    brandFamily: Preferences.defaultCodeFont, monospacedOnly: true)
                Stepper(value: $preferences.codeSize, in: 10...24, step: 0.5) {
                    LabeledContent("Code size", value: points(preferences.codeSize))
                }
            }
            Section {
                Slider(value: $preferences.lineHeight, in: 1.2...2.2, step: 0.05) {
                    LabeledContent(
                        "Line height", value: preferences.lineHeight.formatted(.number.precision(.fractionLength(2))))
                }
                Slider(value: $preferences.maxLineWidth, in: 480...1200, step: 20) {
                    LabeledContent("Line width", value: points(preferences.maxLineWidth))
                }
            }
            Section {
                Toggle("Show markdown markers on every line", isOn: $preferences.showsMarkers)
                Toggle("Typewriter scrolling", isOn: $preferences.typewriterScrolling)
                Toggle("Fade other blocks in focus mode", isOn: $preferences.focusDimming)
            } footer: {
                Text(
                    // swiftlint:disable:next line_length
                    "Markers like # and ** normally show only on the block you're writing in. Typewriter scrolling keeps that line in the middle of the window."
                )
                .foregroundStyle(.secondary)
            }
            Section {
                Button("Restore Defaults") { preferences.resetEditor() }
            }
        }
        .formStyle(.grouped)
    }

    private func points(_ value: Double) -> String {
        String(localized: "\(value.formatted(.number.precision(.fractionLength(0...1)))) pt")
    }
}

/// A font family menu: the brand font first, then everything installed.
private struct FontPicker: View {
    let title: String
    @Binding var family: String
    let brandFamily: String
    let monospacedOnly: Bool

    var body: some View {
        Picker(title, selection: $family) {
            Text(brandFamily).tag(brandFamily)
            Divider()
            ForEach((monospacedOnly ? Self.monospaced : Self.all).filter { $0 != brandFamily }, id: \.self) { name in
                Text(name).tag(name)
            }
        }
    }

    @MainActor static let all = families(monospaced: false)
    @MainActor static let monospaced = families(monospaced: true)

    /// Installed families, monospaced ones only for code.
    static func families(monospaced: Bool) -> [String] {
        let manager = NSFontManager.shared
        guard monospaced else { return manager.availableFontFamilies }
        return manager.availableFontFamilies.filter { family in
            guard let member = manager.availableMembers(ofFontFamily: family)?.first,
                let name = member.first as? String, let font = NSFont(name: name, size: 12)
            else { return false }
            return font.isFixedPitch || font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        }
    }
}
