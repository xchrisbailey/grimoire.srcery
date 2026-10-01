import CoreGraphics
import Foundation

extension NSAttributedString.Key {
    /// A `LineDecoration` on every character of a line that gets drawn chrome.
    public static let grimoireDecoration = NSAttributedString.Key("computer.srcery.grimoire.decoration")
    /// The destination of a link, as written in the markdown.
    public static let grimoireLink = NSAttributedString.Key("computer.srcery.grimoire.link")
    /// Marks markdown syntax (`#`, `**`, list markers), which Preview dims or hides.
    public static let grimoireMarker = NSAttributedString.Key("computer.srcery.grimoire.marker")
}

/// Chrome drawn behind or beside one line of text: code backgrounds, the quote bar,
/// rules, bullets, checkboxes and image previews.
public final class LineDecoration: NSObject, @unchecked Sendable {
    public enum Kind: Equatable {
        /// A line of a fenced or indented code block.
        case code(Position)
        case quote
        case rule
        /// A bullet drawn in place of a hidden list marker, at `indent` points.
        case bullet(indent: CGFloat)
        /// An ordered list keeps its number visible, so nothing is drawn.
        case task(checked: Bool, indent: CGFloat)
        /// A preview of the image at `url`, drawn under the line at `size`.
        case image(url: URL, size: CGSize)
        /// A row of a table drawn as a grid: column edges at `edges` (from the row's start),
        /// with the header row shaded.
        case tableRow(edges: [CGFloat], isHeader: Bool, isLast: Bool)
        /// The table's `| --- |` row, folded down to a line under the header.
        case tableDelimiter
    }

    /// Where a line sits in a multi-line block, for rounding corners.
    public enum Position: Equatable {
        case only, first, middle, last
    }

    public let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public override func isEqual(_ object: Any?) -> Bool {
        (object as? LineDecoration)?.kind == kind
    }

    public override var hash: Int { String(describing: kind).hashValue }
}

extension LineDecoration {
    /// Size of the drawn checkbox.
    public static let checkboxSize: CGFloat = 15
    /// Width reserved for a drawn bullet or checkbox before the text.
    public static let bulletWidth: CGFloat = 18
    public static let taskWidth: CGFloat = 24
    /// Gap between an image line and its preview.
    public static let imageGap: CGFloat = 8
}
