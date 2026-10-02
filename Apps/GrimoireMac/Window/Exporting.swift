import AppKit
import CoreTransferable
import GrimoireCore
import GrimoireEditor
import SwiftUI
import UniformTypeIdentifiers

/// Export as HTML or PDF, Print, Copy as Rich Text, and the PDF the share menu hands out.
@MainActor
extension WindowState {
    /// Settings › General's strict line breaks, off: single line breaks stay breaks.
    private var keepsLineBreaks: Bool { !Preferences.shared.strictLineBreaks }

    private var exportTitle: String {
        document?.url.deletingPathExtension().lastPathComponent ?? String(localized: "Untitled")
    }

    /// The page as HTML in the theme on screen now.
    private func screenHTML() -> String? {
        guard let document else { return nil }
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return DocumentExport.html(
            markdown: document.text, fileURL: document.url, title: exportTitle,
            style: .theme(ThemeLibrary.shared.theme(dark: isDark)), keepsLineBreaks: keepsLineBreaks)
    }

    func exportHTML() {
        guard let html = screenHTML(), let url = askWhereToSave(type: .html, extension: "html") else { return }
        do {
            try Data(html.utf8).write(to: url, options: .atomic)
        } catch {
            actions.error = error
        }
    }

    func exportPDF() {
        guard let url = askWhereToSave(type: .pdf, extension: "pdf") else { return }
        Task {
            do {
                try await makePDF().write(to: url, options: .atomic)
            } catch {
                actions.error = error
            }
        }
    }

    func printDocument() {
        guard let document else { return }
        let printer = PagePrinter()
        printer.title = document.url.lastPathComponent
        let html = DocumentExport.html(
            markdown: document.text, fileURL: document.url, title: exportTitle, style: .print, paged: true,
            keepsLineBreaks: keepsLineBreaks)
        let window = NSApp.keyWindow
        Task {
            do {
                try await printer.load(html)
                try await printer.print(attachedTo: window, jobTitle: document.url.lastPathComponent)
            } catch {
                actions.error = error
            }
        }
    }

    /// The page as a paginated PDF for print.
    func makePDF() async throws -> Data {
        guard let document else { throw PagePrinter.PrintError.couldNotLoad }
        let printer = PagePrinter()
        printer.title = document.url.lastPathComponent
        try await printer.load(
            DocumentExport.html(
                markdown: document.text, fileURL: document.url, title: exportTitle, style: .print, paged: true,
                keepsLineBreaks: keepsLineBreaks))
        return try await printer.pdf()
    }

    /// Puts the selection (or the whole page) on the pasteboard as rich text and HTML, for
    /// Mail, Notes or Slack, with the markdown as plain text.
    func copyAsRichText() {
        guard let document else { return }
        let selected = editor.selectedText
        let markdown = selected.isEmpty ? document.text : selected
        var renderer = HTMLRenderer()
        renderer.keepsLineBreaks = keepsLineBreaks
        renderer.imageSource = { source in
            DocumentExport.dataURI(for: source, relativeTo: document.url.deletingLastPathComponent()) ?? source
        }
        let fragment = renderer.render(markdown)
        let html = "<meta charset=\"utf-8\">" + fragment
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(html, forType: .html)
        pasteboard.setString(markdown, forType: .string)
        if let rich = try? NSAttributedString(
            data: Data(html.utf8),
            options: [
                .documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil),
            let rtf = try? rich.data(
                from: NSRange(location: 0, length: rich.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        {
            pasteboard.setData(rtf, forType: .rtf)
        }
    }

    private func askWhereToSave(type: UTType, extension ext: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = exportTitle + "." + ext
        panel.canCreateDirectories = true
        if let folder = document?.url.deletingLastPathComponent() { panel.directoryURL = folder }
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// The open page as a PDF made on demand, for the share menu.
struct SharedPDF: Transferable {
    let name: String
    let make: @MainActor () async throws -> Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { shared in
            let data = try await shared.make()
            let url = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                .appending(path: shared.name + ".pdf")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            return SentTransferredFile(url)
        }
    }
}

/// The share button in the title bar: the file itself, or the page as a PDF.
struct ShareMenu: View {
    let window: WindowState
    let document: OpenDocument

    var body: some View {
        Menu {
            ShareLink(item: document.url) {
                Label("Share File…", systemImage: "doc")
            }
            ShareLink(
                item: SharedPDF(name: document.url.deletingPathExtension().lastPathComponent) {
                    try await window.makePDF()
                },
                preview: SharePreview(document.url.deletingPathExtension().lastPathComponent + ".pdf")
            ) {
                Label("Share as PDF…", systemImage: "doc.richtext")
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .help(Text("Share the file, or the page as a PDF"))
    }
}
