import Foundation
import Observation

/// The file a window is editing: its text, whether that text is saved, and what to do
/// when the file changes on disk.
///
/// Edits save themselves after a short pause (`autosaveDelay`), and `save()` writes
/// at once for ⌘S and for moments like the window losing focus. Nothing is written
/// when the text matches what's on disk, so opening a file never touches it.
@MainActor @Observable
public final class OpenDocument {
    public private(set) var url: URL
    /// The text in the editor.
    public var text: String {
        didSet {
            guard text != oldValue else { return }
            scheduleAutosave()
        }
    }
    /// The text last read from or written to disk.
    public private(set) var savedText: String
    /// Set when the file changed on disk while there were unsaved edits. Holds the disk text.
    public private(set) var conflict: String?
    /// The last save failure, cleared by the next successful save.
    public private(set) var saveError: Error?

    public var isDirty: Bool { text != savedText }
    public var autosaveDelay: Duration

    private var autosave: Task<Void, Never>?
    private var watcher: FolderWatcher?

    /// Reads `url`. Throws if it can't be read.
    public init(url: URL, autosaveDelay: Duration = .seconds(1)) throws {
        let text = try Self.read(url)
        self.url = url
        self.text = text
        self.savedText = text
        self.autosaveDelay = autosaveDelay
        watch()
    }

    /// Stops watching and saves any pending edits. Call before letting go of the document.
    public func close() {
        save()
        autosave?.cancel()
        watcher?.stop()
        watcher = nil
    }

    /// Stops watching without saving, for a file that was moved to the Trash.
    public func discard() {
        autosave?.cancel()
        watcher?.stop()
        watcher = nil
    }

    /// Writes the text to disk if it has unsaved changes. Holds off while there's a
    /// conflict, so the user's choice decides what wins.
    public func save() {
        autosave?.cancel()
        guard isDirty, conflict == nil else { return }
        write()
    }

    /// The file was renamed or moved (from the tree); follow it.
    public func moved(to newURL: URL) {
        url = newURL
        watch()
    }

    /// Checks the disk against the editor and reloads or flags a conflict.
    public func checkDisk() {
        guard let disk = try? Self.read(url) else { return }
        switch ExternalChange.resolve(saved: savedText, local: text, disk: disk) {
        case .none:
            if disk == text { savedText = disk }
        case .reload(let disk):
            autosave?.cancel()
            savedText = disk
            text = disk
        case .conflict(let disk):
            autosave?.cancel()
            conflict = disk
        }
    }

    /// Resolves a conflict by writing the editor's text over the disk.
    public func keepMine() {
        guard conflict != nil else { return }
        conflict = nil
        write()
    }

    /// Resolves a conflict by taking the disk's text.
    public func loadTheirs() {
        guard let disk = conflict else { return }
        conflict = nil
        savedText = disk
        text = disk
    }

    // MARK: - Private

    private func write() {
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            savedText = text
            saveError = nil
        } catch {
            saveError = error
        }
    }

    private func scheduleAutosave() {
        autosave?.cancel()
        guard isDirty else { return }
        let delay = autosaveDelay
        autosave = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Watches the file's folder, since saves from other editors usually replace the file
    /// rather than write into it.
    private func watch() {
        watcher?.stop()
        let target = url.resolvingSymlinksInPath().path(percentEncoded: false)
        watcher = FolderWatcher(url: url.deletingLastPathComponent()) { [weak self] paths in
            let touched = paths.contains {
                URL(filePath: $0).resolvingSymlinksInPath().path(percentEncoded: false) == target
            }
            guard touched else { return }
            Task { @MainActor in self?.checkDisk() }
        }
    }

    private static func read(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }
}
