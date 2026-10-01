#if os(macOS)
import AppKit
import GrimoireCore
import UniformTypeIdentifiers

/// Paste that understands markdown: images are saved next to the file, a URL pasted over
/// text makes a link, and rich text from browsers becomes markdown.
extension EditorController {
    func paste(from pasteboard: NSPasteboard) -> Bool {
        if let markdown = imageMarkdown(from: pasteboard) {
            insert(markdown, actionName: String(localized: "Paste Image"))
            return true
        }
        if mode == .preview, let table = tableMarkdown(from: pasteboard) {
            insertBlock(table, actionName: String(localized: "Paste Table"))
            return true
        }
        let selection = textView.selectedRange()
        if selection.length > 0, let string = pasteboard.string(forType: .string),
            let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil,
            url.host() != nil || url.scheme == "mailto"
        {
            let label = (textView.string as NSString).substring(with: selection)
            insert("[\(label)](\(url.absoluteString))", actionName: String(localized: "Paste Link"))
            return true
        }
        // Rich text only when there's no plain markdown on the board already.
        if let html = pasteboard.data(forType: .html),
            pasteboard.string(forType: .string).map(Self.looksLikeMarkdown) != true,
            let markdown = HTMLToMarkdown.convert(html: html), !markdown.isEmpty
        {
            insert(markdown, actionName: String(localized: "Paste"))
            return true
        }
        return false
    }

    private func insert(_ text: String, actionName: String) {
        let selection = textView.selectedRange()
        let end = selection.location + text.utf16.count
        apply(
            TextEdit(range: selection.location..<NSMaxRange(selection), replacement: text, selection: end..<end),
            actionName: actionName)
    }

    /// Saves pasted image data, or image files copied in Finder, into the assets folder,
    /// and returns the markdown that shows them.
    private func imageMarkdown(from pasteboard: NSPasteboard) -> String? {
        guard let assets = assetsFolder else { return nil }
        var saved: [URL] = []
        let files =
            (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        for file in files where UTType(filenameExtension: file.pathExtension)?.conforms(to: .image) == true {
            if let copy = try? copyIntoAssets(file, assets: assets) { saved.append(copy) }
        }
        if saved.isEmpty, files.isEmpty, let data = pngData(from: pasteboard) {
            let name = "pasted-\(Self.timestamp()).png"
            if let url = try? write(data, named: name, assets: assets) { saved.append(url) }
        }
        guard !saved.isEmpty else { return nil }
        return saved.map(imageLink).joined(separator: "\n\n")
    }

    /// Where images go: `imageFolder` when set, else `assets/` next to the file.
    var assetsFolder: URL? {
        imageFolder ?? fileURL?.deletingLastPathComponent().appending(path: "assets", directoryHint: .isDirectory)
    }

    /// `![name](path)` for an image saved at `url`, with the path relative to the file.
    func imageLink(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        guard let folder = fileURL?.deletingLastPathComponent() else { return "![\(name)](\(url.lastPathComponent))" }
        return "![\(name)](\(Self.relativePath(from: folder, to: url)))"
    }

    /// A percent-encoded path from `folder` to `file`, climbing with `..` where needed.
    static func relativePath(from folder: URL, to file: URL) -> String {
        let base = folder.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let target = file.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        var shared = 0
        while shared < min(base.count, target.count), base[shared] == target[shared] { shared += 1 }
        let parts = Array(repeating: "..", count: base.count - shared) + target[shared...]
        return parts.map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0 }
            .joined(separator: "/")
    }

    private func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff), let image = NSBitmapImageRep(data: tiff) else { return nil }
        return image.representation(using: .png, properties: [:])
    }

    func copyIntoAssets(_ file: URL, assets: URL) throws -> URL {
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let destination = FileOperations.uniqueURL(
            in: assets, baseName: file.deletingPathExtension().lastPathComponent, extension: file.pathExtension)
        try FileManager.default.copyItem(at: file, to: destination)
        return destination
    }

    private func write(_ data: Data, named name: String, assets: URL) throws -> URL {
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let base = (name as NSString).deletingPathExtension
        let destination = FileOperations.uniqueURL(in: assets, baseName: base, extension: "png")
        try data.write(to: destination)
        return destination
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }

    /// Plain text that's already markdown (copied from another editor) pastes as itself.
    static func looksLikeMarkdown(_ string: String) -> Bool {
        let markers = ["# ", "- ", "* ", "> ", "```", "](", "**"]
        return markers.contains { string.contains($0) }
    }
}
#endif
