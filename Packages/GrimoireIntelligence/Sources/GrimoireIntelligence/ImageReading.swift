import CoreGraphics
import Foundation
import FoundationModels
import GrimoireCore
import Vision

/// Alt text and image-to-markdown, both on the device.
///
/// Image to markdown reads the text with Vision's document recognizer (which finds titles,
/// paragraphs, lists and tables) and writes that out as a markdown draft. When the
/// recognizer found no lists or tables, the model looks at the image and the draft together
/// and returns the blocks, so a slide or a handwritten list still comes out structured.
@MainActor
extension IntelligenceService {
    /// A short description of `image` for its alt text.
    public func describeImage(_ image: CGImage) async throws -> String {
        let request = IntelligenceRequest(
            instructions: Prompts.altText, text: "Describe this image for its alt text.", images: [image],
            temperature: 0.2)
        return Self.altText(try await respond(request))
    }

    /// `image` as markdown: the recognized text, structured by the model. Falls back to the
    /// recognizer's own draft when the model can't help.
    public func markdown(from image: CGImage) async throws -> String {
        let draft = try await ImageText.draft(of: image)
        guard !draft.isEmpty else { throw IntelligenceError.noText }
        // The recognizer's tables and lists are exact; the model only adds structure to plain text.
        if ImageText.hasStructure(draft) { return draft }
        do {
            let request = IntelligenceRequest(
                instructions: Prompts.imageToMarkdown, text: "Text read from the image:\n\n" + draft, images: [image],
                temperature: 0)
            let blocks = try await generate(GeneratedDocument.self, for: request)
            var markdown = blocks.markdown
            // The recognizer's title is reliable; keep it if the model dropped it.
            if let title = draft.components(separatedBy: "\n").first, title.hasPrefix("# "),
                !markdown.contains(title.dropFirst(2))
            {
                markdown = title + "\n\n" + markdown
            }
            return Self.keepsTheText(markdown, of: draft) ? markdown : draft
        } catch let error as IntelligenceError where error == .refused || error == .tooLong {
            return draft
        }
    }

    /// One plain sentence, without "An image of" or a trailing period run.
    nonisolated static func altText(_ text: String) -> String {
        var result = MarkdownText.inline(text).trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'"))
        for lead in ["An image of ", "A picture of ", "Image of ", "A photo of ", "This image shows "]
        where result.lowercased().hasPrefix(lead.lowercased()) {
            result = String(result.dropFirst(lead.count))
            result = result.prefix(1).uppercased() + result.dropFirst()
        }
        while result.hasSuffix(".") { result.removeLast() }
        return result.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
    }

    /// Whether the model's version kept most of the recognized words: a guard against it
    /// inventing content or dropping a table.
    nonisolated static func keepsTheText(_ markdown: String, of draft: String) -> Bool {
        func words(_ text: String) -> Set<String> {
            Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        }
        let expected = words(draft)
        guard !expected.isEmpty else { return true }
        return Double(words(markdown).intersection(expected).count) / Double(expected.count) >= 0.9
    }
}

/// The text in an image, read with Vision's document recognizer.
enum ImageText {
    /// The document as markdown: its title as a heading, then paragraphs, lists and tables
    /// in reading order.
    static func draft(of image: CGImage) async throws -> String {
        do {
            let observations = try await RecognizeDocumentsRequest().perform(on: image)
            return observations.map { markdown(of: $0.document) }.joined(separator: "\n\n")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The document recognizer isn't available on every Mac (virtual machines, for
            // one), so fall back to plain text recognition: the words, a line at a time.
            return try await lines(of: image)
        }
    }

    private static func lines(of image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        let observations = try await request.perform(on: image)
        let sorted = observations.sorted { top($0.boundingBox) > top($1.boundingBox) }
        let texts = sorted.compactMap { $0.topCandidates(1).first?.string }.map { MarkdownText.inline($0) }
        return texts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func markdown(of document: DocumentObservation.Container) -> String {
        var pieces: [(top: CGFloat, text: String)] = []
        let regions =
            document.tables.map(\.boundingRegion.boundingBox) + document.lists.map(\.boundingRegion.boundingBox)
        for table in document.tables {
            pieces.append((top(table.boundingRegion.boundingBox), tableMarkdown(table)))
        }
        for list in document.lists {
            pieces.append((top(list.boundingRegion.boundingBox), listMarkdown(list)))
        }
        let title = document.title?.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        for paragraph in document.paragraphs {
            let box = paragraph.boundingRegion.boundingBox
            guard !regions.contains(where: { contains($0, box) }) else { continue }
            let text = MarkdownText.inline(paragraph.transcript)
            guard !text.isEmpty else { continue }
            pieces.append((top(box), text == title ? "# " + text : text))
        }
        if let title, !title.isEmpty, !pieces.contains(where: { $0.text == "# " + title }) {
            pieces.append((top(document.title!.boundingRegion.boundingBox), "# " + MarkdownText.inline(title)))
        }
        // Vision's coordinates start at the bottom, so the highest top comes first.
        var texts = pieces.sorted { $0.top > $1.top }.map(\.text).filter { !$0.isEmpty }
        // A short line above a table or list is its title.
        if texts.count > 1, hasStructure(texts[1]), isTitleLike(texts[0]) { texts[0] = "## " + texts[0] }
        return texts.joined(separator: "\n\n")
    }

    /// Whether `markdown` has a table or a list in it.
    static func hasStructure(_ markdown: String) -> Bool {
        markdown.components(separatedBy: "\n").contains { line in
            line.hasPrefix("| ") || line.hasPrefix("- ")
                || line.range(of: #"^\d+\. "#, options: .regularExpression) != nil
        }
    }

    private static func isTitleLike(_ text: String) -> Bool {
        text.count < 60 && !text.hasPrefix("#") && !hasStructure(text) && !".:;,".contains(text.last ?? ".")
    }

    private static func tableMarkdown(_ table: DocumentObservation.Container.Table) -> String {
        let width = table.rows.map { row in row.map { $0.columnRange.upperBound + 1 }.max() ?? 0 }.max() ?? 0
        guard width > 0 else { return "" }
        var rows: [[String]] = table.rows.compactMap { row in
            // A cell across the whole table is a caption, already read as a paragraph.
            if row.count == 1, row[0].columnRange.count == width, width > 1 { return nil }
            var cells = Array(repeating: "", count: width)
            for cell in row {
                let text = MarkdownText.inline(cell.content.text.transcript).replacingOccurrences(of: "|", with: "\\|")
                cells[cell.columnRange.lowerBound] = text
            }
            return cells
        }
        // Drop rows and columns with nothing in them.
        rows.removeAll { $0.allSatisfy(\.isEmpty) }
        let used = (0..<width).filter { column in rows.contains { !$0[column].isEmpty } }
        rows = rows.map { row in used.map { row[$0] } }
        guard used.count > 1, rows.count > 1 else {
            return rows.flatMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        }
        return MarkdownTable(rows: rows).markdown
    }

    private static func listMarkdown(_ list: DocumentObservation.Container.List) -> String {
        list.items.enumerated().map { index, item in
            let marker: String
            switch item.markerType {
            case .decimal, .decorativeDecimal, .compositeDecimal: marker = "\(index + 1)."
            default: marker = "-"
            }
            return marker + " " + MarkdownText.inline(item.itemString)
        }.joined(separator: "\n")
    }

    private static func top(_ box: NormalizedRect) -> CGFloat { box.origin.y + box.height }

    private static func contains(_ outer: NormalizedRect, _ inner: NormalizedRect) -> Bool {
        let outer = CGRect(x: outer.origin.x, y: outer.origin.y, width: outer.width, height: outer.height)
        let inner = CGRect(x: inner.origin.x, y: inner.origin.y, width: inner.width, height: inner.height)
        return outer.insetBy(dx: -0.01, dy: -0.01).contains(inner)
    }
}

// MARK: - Generated document

/// A page of markdown blocks, for image to markdown.
@Generable(description: "The content of an image as document blocks, in reading order")
struct GeneratedDocument {
    var blocks: [GeneratedBlock]
}

@Generable
struct GeneratedBlock {
    @Guide(description: "heading, paragraph, bullets, numbered, tasks, or table")
    var kind: String
    @Guide(description: "For a heading: 1 for the main title, 2 for a section")
    var level: Int
    @Guide(description: "The heading or paragraph text; empty for lists and tables")
    var text: String
    @Guide(description: "The list items, or for a table each row's cells joined with \" | \", header row first")
    var items: [String]
}

extension GeneratedDocument {
    var markdown: String {
        blocks.map(\.markdown).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

extension GeneratedBlock {
    var markdown: String {
        let text = MarkdownText.inline(text)
        let items = items.map(MarkdownText.inline).filter { !$0.isEmpty }
        switch kind.lowercased() {
        case "heading": return text.isEmpty ? "" : String(repeating: "#", count: min(max(level, 1), 3)) + " " + text
        case "bullets": return items.map { "- " + $0 }.joined(separator: "\n")
        case "numbered": return items.enumerated().map { "\($0 + 1). " + $1 }.joined(separator: "\n")
        case "tasks": return items.map { "- [ ] " + $0 }.joined(separator: "\n")
        case "table":
            let rows = items.map { $0.split(separator: "|", omittingEmptySubsequences: false).map { String($0) } }
            let width = rows.map(\.count).max() ?? 0
            guard width > 1 else { return items.map { "- " + $0 }.joined(separator: "\n") }
            let padded = rows.map { row in
                (row + Array(repeating: "", count: width - row.count)).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
            }
            return MarkdownTable(rows: padded).markdown
        default: return text.isEmpty ? items.joined(separator: " ") : text
        }
    }
}

extension Prompts {
    static let altText = """
        You write alt text for images in a markdown document: one short plain sentence, under fifteen \
        words, saying what the image shows. Don't start with "An image of". If it's a screenshot, say \
        what it's a screenshot of.
        """
    static let imageToMarkdown = """
        You turn an image (a screenshot, slide, table or handwritten note) into markdown blocks. Use the \
        text read from the image exactly as written; don't add or drop words. Use a heading for a title, \
        lists for lists, and a table for anything laid out in rows and columns.
        """
}
