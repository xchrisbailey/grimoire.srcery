import Foundation

/// One top-level unit of a document, the thing the editor moves, converts and casts.
///
/// A block owns its exact markdown `source`, so a block nobody edits serializes back
/// byte for byte. `trailing` holds the line break and any blank lines that follow it.
public struct Block: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var kind: BlockKind
    /// The block's markdown, without the line break that ends its last line.
    public var source: String
    /// The line break and blank lines between this block and the next one.
    public var trailing: String

    public init(id: UUID = UUID(), kind: BlockKind, source: String, trailing: String = "") {
        self.id = id
        self.kind = kind
        self.source = source
        self.trailing = trailing
    }

    /// The block's content with its markdown markers removed: heading hashes, list markers
    /// and checkboxes, quote markers, and code fences.
    public var text: String { BlockText.extract(from: source, kind: kind) }
}

public enum BlockKind: Hashable, Sendable {
    case paragraph
    case heading(level: Int)
    case listItem(ListItem)
    case blockquote
    case codeBlock(language: String?)
    case table
    case thematicBreak
    /// A paragraph that holds nothing but one image.
    case image
    case html
    /// MDX `import` / `export` statements or a JSX element, kept as opaque source.
    case mdx
    /// Link reference definitions (`[id]: /url`), which produce no visible block.
    case linkDefinitions

    public var isListItem: Bool {
        if case .listItem = self { return true }
        return false
    }
}

public struct ListItem: Hashable, Sendable {
    public enum Marker: Hashable, Sendable {
        case bullet
        case ordered(Int)
    }

    public enum Checkbox: Hashable, Sendable {
        case unchecked
        case checked
    }

    public var marker: Marker
    /// Set for task list items.
    public var checkbox: Checkbox?
    /// Nesting depth, 0 for a top-level item.
    public var indent: Int

    public init(marker: Marker, checkbox: Checkbox? = nil, indent: Int = 0) {
        self.marker = marker
        self.checkbox = checkbox
        self.indent = indent
    }

    public static let bullet = ListItem(marker: .bullet)
    public static let task = ListItem(marker: .bullet, checkbox: .unchecked)
    public static func ordered(_ number: Int = 1) -> ListItem { ListItem(marker: .ordered(number)) }
}
