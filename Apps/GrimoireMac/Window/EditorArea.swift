import GrimoireCore
import GrimoireEditor
import SwiftUI

/// The detail column: the open document, or an empty state when nothing is selected.
struct EditorArea: View {
    let window: WindowState

    var body: some View {
        VStack(spacing: 0) {
            if let document = window.document {
                DocumentBanners(document: document)
                if window.editor.isFindVisible { FindBar(proxy: window.editor) }
                FrontmatterSuggestionBar(document: document, window: window)
                if let offer = window.altTextOffer { AltTextBar(offer: offer, window: window) }
                DocumentEditor(document: document, window: window)
                    // The title bar proxy icon, so the file can be dragged or ⌘-clicked like any document.
                    .navigationDocument(document.url)
            } else if let error = window.openError, let url = window.selectedFile {
                message(String(localized: "Couldn't open \(url.lastPathComponent). \(error.localizedDescription)"))
            } else if window.workspace?.project?.roots.isEmpty ?? true {
                message(String(localized: "This grimoire is empty. Bind a folder to begin."))
            } else {
                message(String(localized: "Choose a page in the sidebar, or conjure a new one."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brand(\.page))
        .sheet(item: Bindable(window).imageMarkdown) { draft in ImageMarkdownSheet(draft: draft, window: window) }
        .sheet(isPresented: Bindable(window).showsVersions) {
            if let document = window.document { VersionBrowser(document: document, editor: window.editor) }
        }
        .overlay(alignment: .bottom) {
            if let text = window.document?.text, showsWordCount {
                WordCountStatus(
                    text: text, wordsPerMinute: Preferences.shared.readingSpeed, inFocusMode: window.focusMode)
            }
        }
    }

    private var showsWordCount: Bool {
        switch Preferences.shared.wordCount {
        case .always: true
        case .focusMode: window.focusMode
        case .never: false
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .brandFont(.body)
            .foregroundStyle(Color.brand(\.overlay1))
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The live-styled markdown editor for the open document.
private struct DocumentEditor: View {
    @Bindable var document: OpenDocument
    let window: WindowState
    private var preferences: Preferences { .shared }

    var body: some View {
        MarkdownEditor(
            text: $document.text, fileURL: document.url, mode: window.editorMode,
            theme: ThemeLibrary.shared.editorTheme(preferences),
            placeholder: String(localized: "A blank page. Type / to cast a block.")
        ) { url in
            window.openLinkedFile(url)
        }
        .dimmingAroundCaret(window.focusMode && window.editorMode == .preview && preferences.focusDimming)
        .showingAllMarkers(preferences.showsMarkers)
        .typewriterScrolling(preferences.typewriterScrolling)
        .focus(on: preferences.focusUnit)
        .autoPairs(preferences.autoPairs)
        .lineNumbers(preferences.showsLineNumbers)
        .indentsWithTabs(preferences.indentsWithTabs)
        .keyBindings(
            EditorKeyBindings(
                toggleTask: preferences.shortcut(for: .toggleTask),
                duplicateBlock: preferences.shortcut(for: .duplicateBlock),
                writingTools: preferences.shortcut(for: .writingTools))
        )
        .imageFolder(window.imageFolder(for: document.url))
        .onImageError { window.actions.error = $0 }
        .proxy(window.editor)
        .onBeforeLargeEdit { reason in document.keepVersion(reason) }
        .intelligence(enabled: window.intelligenceReady) { cast in window.runIntelligence(cast) }
        .textChecking(preferences.textChecking) { preferences.update(from: $0) }
        .projectDictionary(window.project?.dictionary ?? []) { word in
            guard let id = window.projectID else { return }
            window.library.learnWord(word, in: id)
        }
        .onEscape {
            guard window.focusMode else { return false }
            window.setFocusMode(false)
            return true
        }
    }
}

/// The quiet line at the foot of the page: word count and reading time, and in focus
/// mode, how to leave.
private struct WordCountStatus: View {
    let text: String
    let wordsPerMinute: Double
    let inFocusMode: Bool

    private var words: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count { $0.contains { $0.isLetter || $0.isNumber } }
    }

    var body: some View {
        HStack(spacing: 18) {
            Text("\(words) words")
            Text("\(max(1, Int((Double(words) / max(wordsPerMinute, 1)).rounded()))) min read")
            if inFocusMode { Text("esc to wake") }
        }
        .font(.brand(.metadata))
        .foregroundStyle(Color.brand(\.overlay0))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(inFocusMode ? .clear : Color.brand(\.page).opacity(0.9), in: .capsule)
        .padding(.bottom, inFocusMode ? 18 : 10)
        .allowsHitTesting(false)
    }
}

/// The conflict banner (keep mine / load theirs) and save errors, above the editor.
private struct DocumentBanners: View {
    let document: OpenDocument

    var body: some View {
        if document.conflict != nil {
            banner(
                String(localized: "\(document.url.lastPathComponent) changed on disk while you were editing."),
                tint: Color.brand(\.callout)
            ) {
                Button("Keep Mine") { document.keepMine() }
                Button("Load Theirs") { document.loadTheirs() }
            }
        } else if let error = document.saveError {
            banner(saveMessage(error), tint: Color.brand(\.error)) {
                Button("Try Again") { document.save() }
            }
        }
    }

    private func saveMessage(_ error: Error) -> String {
        let name = document.url.lastPathComponent
        let code = (error as? CocoaError)?.code
        if code == .fileWriteNoPermission || code == .fileWriteVolumeReadOnly {
            return String(localized: "Couldn't save \(name). The folder is read-only.")
        }
        return String(localized: "Couldn't save \(name). \(error.localizedDescription)")
    }

    private func banner(_ text: String, tint: Color, @ViewBuilder actions: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
            Text(text)
                .brandFont(.chrome)
                .foregroundStyle(Color.brand(\.ink))
            Spacer()
            actions()
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}
