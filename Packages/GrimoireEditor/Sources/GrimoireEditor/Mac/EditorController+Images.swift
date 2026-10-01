#if os(macOS)
import AppKit
import GrimoireCore

/// Alt text and image to markdown (#20): the editor says which image, and the app runs the
/// model and hands back the alt text or the markdown.
extension EditorController {
    /// Tells the app about images just pasted or picked, so it can describe them.
    func imagesAdded(_ urls: [URL]) {
        guard intelligenceEnabled else { return }
        for url in urls {
            onIntelligence?(
                IntelligenceCast(
                    command: "alt", source: url.path(percentEncoded: false), range: NSRange(location: 0, length: 0)))
        }
    }

    /// The image link at the caret, or at `offset`.
    func imageLink(at offset: Int? = nil) -> ImageLink? {
        ImageLink.at(offset ?? textView.selectedRange().location, in: textView.string)
    }

    /// Runs `describe` or `transcribe` on the image at the caret, or at `offset`.
    public func runImageAction(_ action: String, at offset: Int? = nil) {
        guard let link = imageLink(at: offset), let url = link.fileURL(relativeTo: fileURL?.deletingLastPathComponent())
        else { return NSSound.beep() }
        onIntelligence?(
            IntelligenceCast(command: action, source: url.path(percentEncoded: false), range: link.range))
    }

    /// Fills in the alt text of every link to the image at `url`, as one undoable edit.
    /// Returns false when the image isn't in the page any more.
    @discardableResult
    public func setAltText(_ alt: String, forImageAt url: URL) -> Bool {
        let folder = fileURL?.deletingLastPathComponent()
        let target = url.standardizedFileURL.resolvingSymlinksInPath()
        let links = ImageLink.all(in: textView.string).filter {
            $0.fileURL(relativeTo: folder)?.resolvingSymlinksInPath() == target
        }
        guard !links.isEmpty else { return false }
        let alt = ImageLink.escapedAlt(alt)
        let text = textView.string as NSString
        // One edit from the first alt text to the last, so it undoes in one step.
        let start = links[0].altRange.location
        let end = NSMaxRange(links[links.count - 1].altRange)
        var replacement = ""
        var cursor = start
        for link in links {
            replacement +=
                text.substring(with: NSRange(location: cursor, length: link.altRange.location - cursor)) + alt
            cursor = NSMaxRange(link.altRange)
        }
        let caret = textView.selectedRange().location
        let shift = links.filter { NSMaxRange($0.altRange) <= caret }.reduce(0) {
            $0 + alt.utf16.count - $1.altRange.length
        }
        let selection = caret > end ? caret + shift : min(caret, start + replacement.utf16.count)
        apply(
            TextEdit(range: start..<end, replacement: replacement, selection: selection..<selection),
            actionName: String(localized: "Describe Image"))
        return true
    }

    /// Puts `markdown` in as its own block after `range` (an image's link), or at the caret.
    public func insertBlock(_ markdown: String, after range: NSRange?, actionName: String) {
        if let range {
            textView.setSelectedRange(NSRange(location: min(NSMaxRange(range), textView.string.utf16.count), length: 0))
        }
        insertBlock(markdown, actionName: actionName)
    }

    /// Describe Image and Image to Markdown, for the image under the click.
    func imageMenuItems(at offset: Int) -> [NSMenuItem] {
        guard intelligenceEnabled, imageLink(at: offset) != nil else { return [] }
        return [
            MenuClosure.item(String(localized: "Describe Image")) { [weak self] in
                self?.runImageAction("describe", at: offset)
            },
            MenuClosure.item(String(localized: "Image to Markdown…")) { [weak self] in
                self?.runImageAction("transcribe", at: offset)
            },
        ]
    }
}
#endif
