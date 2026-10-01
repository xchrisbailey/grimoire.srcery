import AppKit
import GrimoireCore
import GrimoireEditor
import GrimoireIntelligence
import ImageIO
import SwiftUI

/// Alt text offered for an image: still being written while `alt` is nil.
struct AltTextOffer: Equatable {
    var image: URL
    var alt: String?
}

/// An image read as markdown, waiting in a sheet to be checked and put in.
struct ImageMarkdownDraft: Identifiable, Equatable {
    let id = UUID()
    /// Nil while the image is still being read.
    var markdown: String?
    /// The image's link, to put the markdown after; nil for the caret.
    var after: NSRange?
}

/// Alt text and image to markdown (#20): runs the model on an image and offers the result.
@MainActor
extension WindowState {
    /// Handles the image commands from the editor. False for anything else.
    func runImageCommand(_ cast: IntelligenceCast) -> Bool {
        let url = URL(filePath: cast.source)
        switch cast.command {
        case "alt":
            switch Preferences.shared.altText {
            case .never: break
            case .ask: offerAltText(for: url)
            case .always: describe(url, apply: true)
            }
        case "describe":
            offerAltText(for: url)
        case "transcribe":
            guard let image = Self.loadImage(url) else {
                actions.error = IntelligenceError.noText
                return true
            }
            readAsMarkdown(image, after: cast.range)
        default:
            return false
        }
        return true
    }

    /// Reads the image on the clipboard as markdown, for a look before it goes in.
    func pasteImageAsMarkdown() {
        guard let image = NSImage(pasteboard: .general)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            NSSound.beep()
            return
        }
        readAsMarkdown(image, after: nil)
    }

    private func offerAltText(for url: URL) {
        altTextOffer = AltTextOffer(image: url, alt: nil)
        describe(url, apply: false)
    }

    private func describe(_ url: URL, apply: Bool) {
        Task {
            do {
                guard let image = Self.loadImage(url) else { throw IntelligenceError.noText }
                let alt = try await IntelligenceService.shared.describeImage(image)
                if apply {
                    editor.setAltText(alt, forImageAt: url)
                } else if altTextOffer?.image == url {
                    altTextOffer?.alt = alt
                }
            } catch {
                if altTextOffer?.image == url { altTextOffer = nil }
                actions.error = error
            }
        }
    }

    /// Fills in the offered alt text.
    func acceptAltText() {
        guard let offer = altTextOffer, let alt = offer.alt else { return }
        altTextOffer = nil
        if !editor.setAltText(alt, forImageAt: offer.image) { NSSound.beep() }
    }

    private func readAsMarkdown(_ image: CGImage, after range: NSRange?) {
        let draft = ImageMarkdownDraft(markdown: nil, after: range)
        imageMarkdown = draft
        Task {
            do {
                let markdown = try await IntelligenceService.shared.markdown(from: image)
                if imageMarkdown?.id == draft.id { imageMarkdown?.markdown = markdown }
            } catch {
                if imageMarkdown?.id == draft.id { imageMarkdown = nil }
                actions.error = error
            }
        }
    }

    /// Puts the checked markdown in.
    func insertImageMarkdown(_ markdown: String, after range: NSRange?) {
        imageMarkdown = nil
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        editor.insertBlock(markdown, after: range, actionName: String(localized: "Image to Markdown"))
    }

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

/// Above the page: alt text written for an image, to add or leave.
struct AltTextBar: View {
    let offer: AltTextOffer
    let window: WindowState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo").foregroundStyle(Color.brand(\.magic))
            if let alt = offer.alt {
                Text("Alt text for \(offer.image.lastPathComponent): “\(alt)”")
                    .brandFont(.chrome)
                    .foregroundStyle(Color.brand(\.ink))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Add") { window.acceptAltText() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Text("Describing \(offer.image.lastPathComponent)…")
                    .brandFont(.chrome)
                    .foregroundStyle(Color.brand(\.subtext))
                Spacer()
                ProgressView().controlSize(.small)
            }
            Button("Not now") { window.altTextOffer = nil }
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.brand(\.magic).opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// The markdown read from an image, editable, before it goes in.
struct ImageMarkdownSheet: View {
    let draft: ImageMarkdownDraft
    let window: WindowState
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Image to Markdown").font(.headline)
            if draft.markdown == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the image…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $text)
                    .font(.brand(.raw))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.brand(\.surface0), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                Spacer()
                Button("Cancel") { window.imageMarkdown = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Insert") { window.insertImageMarkdown(text, after: draft.after) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.markdown == nil)
            }
        }
        .padding(20)
        .frame(width: 560, height: 420)
        .onChange(of: draft.markdown, initial: true) { _, markdown in
            if let markdown { text = markdown }
        }
    }
}
