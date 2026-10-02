import GrimoireCore
import GrimoireEditor
import SwiftUI

/// Settings › Editor: line height and width, and how the page behaves. Fonts are in
/// Settings › Appearance.
struct EditorSettings: View {
    @State private var preferences = Preferences.shared

    var body: some View {
        Form {
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
