import GrimoireCore
import GrimoireEditor
import SwiftUI

/// Settings › Spelling: the checks and substitutions (the same switches as Edit › Spelling
/// and Grammar and Edit › Substitutions), and each project's own words.
struct SpellingSettings: View {
    @State private var preferences = Preferences.shared
    @Environment(ProjectLibrary.self) private var library
    @State private var project: Project.ID?
    @State private var newWord = ""

    var body: some View {
        Form {
            Section {
                Toggle("Check spelling while typing", isOn: $preferences.checksSpelling)
                Toggle("Check grammar with spelling", isOn: $preferences.checksGrammar)
                    .disabled(!preferences.checksSpelling)
                Toggle("Correct spelling automatically", isOn: $preferences.correctsSpelling)
            } footer: {
                Text("Code, links, HTML, MDX and frontmatter are never checked or corrected.")
                    .foregroundStyle(.secondary)
            }
            Section("Substitutions") {
                Toggle("Smart quotes", isOn: $preferences.smartQuotes)
                Toggle("Smart dashes", isOn: $preferences.smartDashes)
                Toggle("Text replacement", isOn: $preferences.textReplacement)
            }
            if !library.projects.isEmpty { dictionarySection }
        }
        .formStyle(.grouped)
        .onAppear { project = project ?? library.projects.first?.id }
    }

    private var dictionarySection: some View {
        Section {
            Picker("Project", selection: $project) {
                ForEach(library.projects) { project in
                    Text(project.name).tag(Optional(project.id))
                }
            }
            if let id = project, let current = library.project(id) {
                ForEach(current.dictionary, id: \.self) { word in
                    HStack {
                        Text(word)
                        Spacer()
                        Button {
                            library.update(id) { $0.dictionary.removeAll { $0 == word } }
                        } label: {
                            Image(systemName: "minus.circle")
                                .accessibilityLabel(Text("Remove \(word)"))
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Add a word", text: $newWord)
                        .onSubmit { add(to: id) }
                    Button("Add") { add(to: id) }
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        } header: {
            Text("Project dictionary")
        } footer: {
            Text(
                "Words here are spelled right in this project's pages. Right-click a misspelled word to add it."
            )
            .foregroundStyle(.secondary)
        }
    }

    private func add(to id: Project.ID) {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        library.learnWord(word, in: id)
        newWord = ""
    }
}

extension ProjectLibrary {
    /// Adds `word` to the project's dictionary, once.
    func learnWord(_ word: String, in id: Project.ID) {
        update(id) { project in
            guard !project.dictionary.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else {
                return
            }
            project.dictionary.append(word)
            project.dictionary.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }
}

extension Preferences {
    /// The checks as the editor takes them.
    var textChecking: TextChecking {
        TextChecking(
            spelling: checksSpelling, grammar: checksSpelling && checksGrammar, correction: correctsSpelling,
            smartQuotes: smartQuotes, smartDashes: smartDashes, textReplacement: textReplacement)
    }

    /// Takes a change made from the Edit menu.
    func update(from checking: TextChecking) {
        checksSpelling = checking.spelling
        if checking.spelling { checksGrammar = checking.grammar }
        correctsSpelling = checking.correction
        smartQuotes = checking.smartQuotes
        smartDashes = checking.smartDashes
        textReplacement = checking.textReplacement
    }
}
