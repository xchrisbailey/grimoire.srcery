import Foundation

/// The `![alt](destination)` images in a page: where their alt text is, and which file each
/// points at. Used to fill in alt text and to find the image under the caret.
public struct ImageLink: Equatable, Sendable {
    /// The whole `![alt](destination "title")`.
    public var range: NSRange
    /// Between the brackets.
    public var altRange: NSRange
    public var alt: String
    public var destination: String

    /// The file the destination points at, relative to `folder` unless it's absolute.
    public func fileURL(relativeTo folder: URL?) -> URL? {
        if let url = URL(string: destination), let scheme = url.scheme {
            return scheme == "file" ? url.standardizedFileURL : nil
        }
        let path = destination.removingPercentEncoding ?? destination
        if path.hasPrefix("/") { return URL(filePath: path).standardizedFileURL }
        return folder?.appending(path: path).standardizedFileURL
    }

    // swiftlint:disable:next force_try
    private static let pattern = try! NSRegularExpression(
        pattern: #"!\[((?:[^\]\\]|\\.)*)\]\(\s*(<[^>]*>|[^\s)]+)(?:\s+"[^"]*")?\s*\)"#)

    /// Every image link in `text`, in order.
    public static func all(in text: String) -> [ImageLink] {
        let string = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: string.length)).map { match in
            var destination = string.substring(with: match.range(at: 2))
            if destination.hasPrefix("<") { destination = String(destination.dropFirst().dropLast()) }
            return ImageLink(
                range: match.range, altRange: match.range(at: 1), alt: string.substring(with: match.range(at: 1)),
                destination: destination)
        }
    }

    /// The image link at `offset`, or on the same line when there's only one there.
    public static func at(_ offset: Int, in text: String) -> ImageLink? {
        let links = all(in: text)
        if let hit = links.first(where: { NSLocationInRange(offset, $0.range) || NSMaxRange($0.range) == offset }) {
            return hit
        }
        let line = (text as NSString).lineRange(
            for: NSRange(location: min(offset, (text as NSString).length), length: 0))
        let onLine = links.filter { NSIntersectionRange($0.range, line).length > 0 }
        return onLine.count == 1 ? onLine[0] : nil
    }

    /// `alt` made safe to sit between the brackets.
    public static func escapedAlt(_ alt: String) -> String {
        alt.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
    }
}
