import GrimoireCore
import GrimoireEditor
import SwiftUI

/// Settings › Editor: line height and width, how the page behaves, Raw mode and the word
/// count. Fonts are in Settings › Appearance.
struct EditorSettings: View {
    @State private var preferences = Preferences.shared

    var body: some View {
        Form {
            Section {
                Slider(value: $preferences.lineHeight, in: 1.2...2.2, step: 0.05) {
                    LabeledContent(
                        "Line height", value: preferences.lineHeight.formatted(.number.precision(.fractionLength(2))))
                }
                Toggle("Limit line length for easier reading", isOn: $preferences.limitsLineWidth)
                Slider(value: $preferences.maxLineWidth, in: 480...1200, step: 20) {
                    LabeledContent("Line width", value: points(preferences.maxLineWidth))
                }
                .disabled(!preferences.limitsLineWidth)
            }
            Section {
                Toggle("Show markdown markers on every line", isOn: $preferences.showsMarkers)
                Toggle("Typewriter scrolling", isOn: $preferences.typewriterScrolling)
                Toggle("Pair brackets, quotes and markdown markers", isOn: $preferences.autoPairs)
                Toggle("Fade other text in focus mode", isOn: $preferences.focusDimming)
                Picker("Keep lit in focus mode", selection: $preferences.focusUnit) {
                    Text("Paragraph").tag(FocusUnit.paragraph)
                    Text("Sentence").tag(FocusUnit.sentence)
                }
                .disabled(!preferences.focusDimming)
            } footer: {
                Text(
                    // swiftlint:disable:next line_length
                    "Markers like # and ** normally show only on the block you're writing in. Typewriter scrolling keeps that line in the middle of the window."
                )
                .foregroundStyle(.secondary)
            }
            SyntaxHighlightSettings(preferences: preferences)
            Section {
                Toggle("Show line numbers", isOn: $preferences.showsLineNumbers)
                Stepper(value: $preferences.tabWidth, in: 1...8) {
                    LabeledContent("Tab width", value: String(localized: "\(preferences.tabWidth) spaces"))
                }
                Picker("Indent with", selection: $preferences.indentsWithTabs) {
                    Text("Spaces").tag(false)
                    Text("Tabs").tag(true)
                }
            } header: {
                Text("Raw mode")
            } footer: {
                Text(
                    // swiftlint:disable:next line_length
                    "Tab width and indenting also apply to code blocks in Preview. List items always indent with spaces."
                )
                .foregroundStyle(.secondary)
            }
            Section("Word count") {
                Picker("Show word count", selection: $preferences.wordCount) {
                    Text("Always").tag(WordCountDisplay.always)
                    Text("In Focus Mode").tag(WordCountDisplay.focusMode)
                    Text("Never").tag(WordCountDisplay.never)
                }
                Stepper(value: $preferences.readingSpeed, in: 100...500, step: 10) {
                    LabeledContent(
                        "Reading speed",
                        value: String(localized: "\(Int(preferences.readingSpeed)) words a minute"))
                }
                .disabled(preferences.wordCount == .never)
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
