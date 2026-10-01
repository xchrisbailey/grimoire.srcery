/// What to do when the open file changes on disk underneath the editor.
public enum ExternalChange: Equatable, Sendable {
    /// Nothing to do: the disk matches what was last saved (often the app's own write
    /// coming back), or it already matches the editor.
    case none
    /// The editor has no unsaved changes, so take the new text silently.
    case reload(String)
    /// Both sides changed. Ask the user: keep mine or load theirs.
    case conflict(disk: String)

    /// - Parameters:
    ///   - saved: The text last read from or written to disk.
    ///   - local: The text in the editor now.
    ///   - disk: The text on disk now.
    public static func resolve(saved: String, local: String, disk: String) -> ExternalChange {
        if disk == saved || disk == local { return .none }
        if local == saved { return .reload(disk) }
        return .conflict(disk: disk)
    }
}
