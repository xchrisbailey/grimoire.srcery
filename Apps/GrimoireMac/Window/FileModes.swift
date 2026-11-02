import Foundation
import GrimoireEditor

/// The mode each file was last shown in. Files not listed open in the default mode.
enum FileModes {
    private static let key = "grimoire.fileModes"
    /// Before files remembered Preview too, only Raw files were listed here.
    private static let legacyKey = "grimoire.rawFiles"
    /// Enough to cover the files anyone works in, without growing forever.
    private static let limit = 300

    static func mode(for url: URL, default fallback: EditorMode = .preview) -> EditorMode {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        if let stored = entries.first(where: { $0.first == path }), stored.count == 2,
            let mode = EditorMode(rawValue: stored[1])
        {
            return mode
        }
        let legacy = UserDefaults.standard.stringArray(forKey: legacyKey) ?? []
        return legacy.contains(path) ? .raw : fallback
    }

    static func remember(_ mode: EditorMode, for url: URL) {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let rest = entries.filter { $0.first != path }
        UserDefaults.standard.set(Array(([[path, mode.rawValue]] + rest).prefix(limit)), forKey: key)
    }

    /// `[path, mode]` pairs, most recent first.
    private static var entries: [[String]] {
        UserDefaults.standard.array(forKey: key) as? [[String]] ?? []
    }
}
