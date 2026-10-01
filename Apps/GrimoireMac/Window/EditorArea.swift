import GrimoireCore
import GrimoireEditor
import SwiftUI

/// The detail column: the open document, or an empty state when nothing is selected.
///
/// The editor is a plain text view until the TextKit 2 editor lands (#6).
struct EditorArea: View {
    let window: WindowState

    var body: some View {
        VStack(spacing: 0) {
            if let document = window.document {
                DocumentBanners(document: document)
                PlaceholderEditor(document: document)
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
        .overlay(alignment: .bottom) {
            if window.focusMode {
                Text("esc to wake")
                    .brandFont(.metadata)
                    .foregroundStyle(Color.brand(\.overlay0))
                    .padding(.bottom, 18)
            }
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

private struct PlaceholderEditor: View {
    @Bindable var document: OpenDocument

    var body: some View {
        TextEditor(text: $document.text)
            .brandFont(.body)
            .foregroundStyle(Color.brand(\.ink))
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 680)
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                if document.text.isEmpty {
                    Text("A blank page. Type / to cast a block.")
                        .brandFont(.body)
                        .foregroundStyle(Color.brand(\.overlay1))
                        .allowsHitTesting(false)
                        .frame(maxWidth: 680, alignment: .leading)
                        .padding(.horizontal, 29)
                        .padding(.top, 30)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
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
