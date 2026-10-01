/// Platform-independent core of Grimoire: the document and block model,
/// markdown parsing and serialization, workspaces, and theme tokens.
///
/// Nothing in this module may import AppKit or UIKit, so the macOS and iOS
/// apps share it unchanged.
public enum GrimoireCore {
    /// File extensions Grimoire opens as documents.
    public static let documentExtensions: Set<String> = ["md", "mdx"]
}
