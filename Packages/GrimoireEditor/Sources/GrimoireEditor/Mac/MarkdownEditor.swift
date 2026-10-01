#if os(macOS)
import AppKit
import GrimoireCore
import SwiftUI

/// The markdown editor as a SwiftUI view: a live-styled TextKit 2 text view over the
/// file's exact text.
public struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var fileURL: URL?
    var placeholder: String?
    var mode: EditorMode
    var theme: EditorTheme
    var dimsAroundCaret = false
    var showsAllMarkers = false
    var typewriterScrolling = false
    var imageFolder: URL?
    var textChecking = TextChecking.spellingOnly
    var projectWords: [String] = []
    var onLearnWord: ((String) -> Void)?
    var onTextCheckingChange: ((TextChecking) -> Void)?
    var onEscape: (() -> Bool)?
    var onOpenFile: (URL) -> Void

    /// - Parameters:
    ///   - fileURL: The file being edited, for resolving relative links and images and
    ///     choosing `.md` or `.mdx` parsing.
    ///   - theme: The light and dark themes and the editor's sizes.
    ///   - placeholder: Shown while the file is empty.
    ///   - onOpenFile: Called for a ⌘-clicked link to another markdown file.
    public init(
        text: Binding<String>, fileURL: URL?, mode: EditorMode = .preview, theme: EditorTheme = EditorTheme(),
        placeholder: String? = nil, onOpenFile: @escaping (URL) -> Void = { _ in }
    ) {
        _text = text
        self.fileURL = fileURL
        self.mode = mode
        self.theme = theme
        self.placeholder = placeholder
        self.onOpenFile = onOpenFile
    }

    /// Fades everything but the caret's block, for focus mode.
    public func dimmingAroundCaret(_ dims: Bool) -> MarkdownEditor {
        var copy = self
        copy.dimsAroundCaret = dims
        return copy
    }

    /// Shows markdown markers on every block, not just the caret's.
    public func showingAllMarkers(_ shows: Bool) -> MarkdownEditor {
        var copy = self
        copy.showsAllMarkers = shows
        return copy
    }

    /// Keeps the caret's line in the middle of the view while typing.
    public func typewriterScrolling(_ isOn: Bool) -> MarkdownEditor {
        var copy = self
        copy.typewriterScrolling = isOn
        return copy
    }

    /// Saves pasted and picked images in `folder` instead of `assets/` next to the file.
    public func imageFolder(_ folder: URL?) -> MarkdownEditor {
        var copy = self
        copy.imageFolder = folder
        return copy
    }

    /// Spelling, grammar and substitution checks, with a callback for when the Edit menu
    /// changes one.
    public func textChecking(_ checking: TextChecking, onChange: @escaping (TextChecking) -> Void) -> MarkdownEditor {
        var copy = self
        copy.textChecking = checking
        copy.onTextCheckingChange = onChange
        return copy
    }

    /// Words the spell checker accepts in this project, and what to do when one is learned.
    public func projectDictionary(_ words: [String], onLearn: @escaping (String) -> Void) -> MarkdownEditor {
        var copy = self
        copy.projectWords = words
        copy.onLearnWord = onLearn
        return copy
    }

    /// Handles Escape before the editor does; return true when it was handled.
    public func onEscape(_ action: @escaping () -> Bool) -> MarkdownEditor {
        var copy = self
        copy.onEscape = action
        return copy
    }

    private var flavor: DocumentFlavor {
        fileURL.flatMap { DocumentFlavor(pathExtension: $0.pathExtension) } ?? .markdown
    }

    public func makeCoordinator() -> EditorController {
        EditorController()
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let controller = context.coordinator
        controller.styler.theme.isDark = controller.textView.isDarkAppearance
        controller.theme = theme
        controller.fileURL = fileURL
        controller.styler.baseURL = fileURL?.deletingLastPathComponent()
        controller.styler.mode = mode
        controller.load(text, flavor: flavor)
        wire(controller)
        return controller.scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let controller = context.coordinator
        wire(controller)
        if controller.fileURL != fileURL {
            let isSameText = text == controller.lastText
            controller.fileURL = fileURL
            controller.styler.baseURL = fileURL?.deletingLastPathComponent()
            // The same text under a new URL is a rename or move; anything else is a new file.
            if isSameText {
                controller.restyleAll()
            } else {
                controller.styler.mode = mode
                controller.load(text, flavor: flavor)
            }
        } else if text != controller.lastText {
            controller.replaceText(text, flavor: flavor)
        }
        controller.mode = mode
        controller.theme = theme
        controller.dimsAroundCaret = dimsAroundCaret
    }

    private func wire(_ controller: EditorController) {
        controller.textView.placeholder = placeholder
        controller.imageFolder = imageFolder
        controller.revealsAllMarkers = showsAllMarkers
        controller.typewriterScrolling = typewriterScrolling
        controller.textChecking = textChecking
        controller.projectWords = projectWords
        controller.onLearnWord = onLearnWord
        controller.onTextCheckingChange = onTextCheckingChange
        controller.onEscape = onEscape
        let binding = $text
        controller.onTextChange = { binding.wrappedValue = $0 }
        let fileURL = fileURL
        let onOpenFile = onOpenFile
        controller.onOpenLink = { destination in
            Self.open(destination, from: fileURL, onOpenFile: onOpenFile)
        }
    }

    /// Opens a ⌘-clicked link: web links in the browser, markdown files in the editor,
    /// other files with their default app.
    static func open(_ destination: String, from fileURL: URL?, onOpenFile: (URL) -> Void) {
        let trimmed = destination.trimmingCharacters(in: .whitespaces)
        if let url = URL(string: trimmed), let scheme = url.scheme, scheme != "file" {
            NSWorkspace.shared.open(url)
            return
        }
        let path = (trimmed.split(separator: "#", maxSplits: 1).first.map(String.init) ?? "")
        guard !path.isEmpty, let folder = fileURL?.deletingLastPathComponent() else { return }
        let decoded = path.removingPercentEncoding ?? path
        let target =
            decoded.hasPrefix("/") ? URL(filePath: decoded) : folder.appending(path: decoded).standardizedFileURL
        if GrimoireCore.documentExtensions.contains(target.pathExtension.lowercased()) {
            onOpenFile(target)
        } else {
            NSWorkspace.shared.open(target)
        }
    }
}
#endif
