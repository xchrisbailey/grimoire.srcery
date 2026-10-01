import Foundation
import FoundationModels
import GrimoireCore

/// The markdown-aware writing commands: the AI spells (/continue, /summarize, /outline,
/// /table, /todo, /translate) and the selection actions (rewrite, shorten, expand, explain).
///
/// Structured commands use guided generation, so the model returns blocks (headings, list
/// items, table cells) that are written out as markdown here and always parse.
public enum WritingCommand: Equatable, Sendable {
    case continueWriting
    case summarize
    case outline
    case table
    case todo
    case translate(language: String)
    case rewrite
    case shorten
    case expand
    case explainCode
}

/// What a command works on.
public struct WritingContext: Sendable {
    /// The text the command reads: the paragraph to continue, the section to summarize,
    /// the selection to rewrite.
    public var source: String
    /// The code block's language, for explaining code.
    public var language: String?

    public init(source: String, language: String? = nil) {
        self.source = source
        self.language = language
    }
}

@MainActor
extension IntelligenceService {
    /// Streams the markdown `command` produces for `context`, the whole text so far each time.
    public func stream(_ command: WritingCommand, context: WritingContext) -> AsyncThrowingStream<String, Error> {
        let source = context.source
        switch command {
        case .continueWriting:
            let request = IntelligenceRequest(instructions: Prompts.continuing, text: String(source.suffix(6_000)))
            return mapped(stream(request)) { Self.continuation($0, of: source) }
        case .summarize:
            return summarize(source)
        case .outline:
            let request = IntelligenceRequest(instructions: Prompts.outline, text: "Topic: \(source)")
            return streamGenerated(GeneratedOutline.self, for: request) { $0.markdown }
        case .table:
            let request = IntelligenceRequest(instructions: Prompts.table, text: source)
            return streamGenerated(GeneratedTable.self, for: request) { $0.markdown }
        case .todo:
            let request = IntelligenceRequest(instructions: Prompts.todo, text: source)
            return streamGenerated(GeneratedTasks.self, for: request) { $0.markdown }
        case .translate(let language):
            return stream(IntelligenceRequest(instructions: Prompts.translate(into: language), text: source))
        case .rewrite, .shorten, .expand:
            return stream(IntelligenceRequest(instructions: Self.editInstructions(command), text: source))
        case .explainCode:
            let code = "```\(context.language ?? "")\n\(source)\n```"
            return stream(IntelligenceRequest(instructions: Prompts.explainCode, text: code))
        }
    }

    /// A continuation as it goes after `source`: without the line it continues when the model
    /// repeats it, and with a space before it when it carries on a word.
    nonisolated static func continuation(_ response: String, of source: String) -> String {
        let line = (source.components(separatedBy: "\n").last ?? "").trimmingCharacters(in: .whitespaces)
        var text = Substring(response).drop { $0.isWhitespace }
        if line.count >= 8 {
            if line.hasPrefix(text) { return "" }
            if text.hasPrefix(line) { text = text.dropFirst(line.count).drop { $0.isWhitespace } }
        }
        guard let first = text.first, let last = source.last, !last.isWhitespace else { return String(text) }
        let attaches = first.isPunctuation && !"([\"'“‘*_`".contains(first)
        return (attaches ? "" : " ") + text
    }

    private func mapped(
        _ stream: AsyncThrowingStream<String, Error>, _ transform: @escaping @Sendable (String) -> String
    ) -> AsyncThrowingStream<String, Error> {
        let (output, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let task = Task {
            do {
                for try await text in stream { continuation.yield(transform(text)) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return output
    }

    private static func editInstructions(_ command: WritingCommand) -> String {
        let task =
            switch command {
            case .shorten: "Make it shorter, keeping its meaning."
            case .expand: "Expand it with a little more detail in the same voice."
            default: "Rewrite it to read more clearly, in the same voice and about the same length."
            }
        return """
            You edit a passage of markdown. \(task) Keep every link, link destination, code span, \
            emphasis marker and list marker. Answer with the edited passage alone.
            """
    }

    /// A summary as a callout. Text too long for one pass is summarized section by section on
    /// the device, then the summaries are summarized, unless Private Cloud Compute is allowed.
    func summarize(_ text: String) -> AsyncThrowingStream<String, Error> {
        let instructions = "You summarize markdown notes in two to four plain sentences."
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let task = Task { @MainActor in
            do {
                var source = text
                let tokens = await self.tokenCount(text)
                if (try? await self.route(forTokens: tokens)) == nil {
                    source = try await self.summarizeInParts(text, instructions: instructions)
                }
                for try await summary in self.stream(IntelligenceRequest(instructions: instructions, text: source)) {
                    continuation.yield(Self.callout(summary))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// Summaries of each piece of `text` small enough for the on-device model, joined.
    private func summarizeInParts(_ text: String, instructions: String) async throws -> String {
        let budget = (contextSize - Self.responseReserve) * 2  // about two characters a token, conservatively
        var summaries: [String] = []
        for part in Self.parts(of: text, maxCharacters: max(1_000, budget)) {
            summaries.append(
                try await respond(IntelligenceRequest(instructions: instructions, text: part, route: .onDevice)))
        }
        return summaries.joined(separator: "\n\n")
    }

    /// Splits markdown at headings, then at paragraphs, into pieces under `maxCharacters`.
    static func parts(of text: String, maxCharacters: Int) -> [String] {
        var parts: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: "\n\n") {
            let startsSection = paragraph.hasPrefix("#")
            if !current.isEmpty, current.count + paragraph.count + 2 > maxCharacters || startsSection {
                parts.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n\n") + String(paragraph.prefix(maxCharacters))
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    /// `text` as a `> [!NOTE]` callout.
    static func callout(_ text: String) -> String {
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        return "> [!NOTE]\n" + lines.map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
    }
}

/// The instructions each writing command gives the model.
private enum Prompts {
    static let continuing = """
        You continue a markdown document in the author's own voice, picking up exactly where the text \
        stops. If it stops mid-sentence, your first words finish that sentence. Then write a few more \
        sentences that follow on. Don't repeat the text, don't summarize it, and don't add a heading. \
        Use plain markdown.
        """
    static let outline = "You turn a topic into a short outline for a markdown document."
    static let table = """
        You turn a list or a passage into a table. Pick a few clear columns and keep the facts exactly \
        as written.
        """
    static let todo = """
        You find the action items in notes: things someone needs to do. Each is a short imperative \
        phrase. Leave out anything that's already done or isn't a task.
        """
    static let explainCode = """
        You explain code to a reader of a markdown document in a few plain sentences: what it does and \
        anything surprising. Don't repeat the code.
        """

    static func translate(into language: String) -> String {
        """
        You translate markdown into \(language). Keep every markdown marker, link destination, code span \
        and code block exactly as they are; translate only the prose. Answer with the translation alone.
        """
    }
}

// MARK: - Frontmatter

/// A suggested title, tags and summary for a page with no frontmatter.
@Generable(description: "Frontmatter for a markdown page")
public struct FrontmatterSuggestion: Equatable, Sendable {
    @Guide(description: "A short title for the page")
    public var title: String
    @Guide(description: "One to five lowercase tags, single words or hyphenated", .count(1...5))
    public var tags: [String]
    @Guide(description: "One sentence saying what the page is about")
    public var summary: String

    public init(title: String, tags: [String], summary: String) {
        self.title = title
        self.tags = tags
        self.summary = summary
    }

    /// The suggestion as a YAML frontmatter block, with a blank line after it.
    public var yaml: String {
        func quoted(_ value: String) -> String {
            let flat = MarkdownText.inline(value)
            return "\"" + flat.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                + "\""
        }
        let tagList = tags.map { MarkdownText.inline($0).lowercased().replacingOccurrences(of: " ", with: "-") }
        return
            "---\ntitle: \(quoted(title))\ntags: [\(tagList.joined(separator: ", "))]\n"
            + "summary: \(quoted(summary))\n---\n\n"
    }
}

@MainActor
extension IntelligenceService {
    /// A title, tags and summary for `text`, from its first few thousand characters.
    public func suggestFrontmatter(for text: String) async throws -> FrontmatterSuggestion {
        try await generate(
            FrontmatterSuggestion.self,
            for: IntelligenceRequest(
                instructions: "You suggest frontmatter for a markdown page: a title, tags and a one-sentence summary.",
                text: String(text.prefix(5_000)), temperature: 0.2))
    }
}

// MARK: - Generated blocks

/// An outline: a heading and its points.
@Generable(description: "An outline for a section of a document")
struct GeneratedOutline {
    @Guide(description: "A short heading for the topic, in title case")
    var heading: String
    @Guide(description: "Three to seven points, each a short phrase", .count(3...7))
    var points: [GeneratedPoint]
}

@Generable
struct GeneratedPoint {
    var text: String
    @Guide(description: "Zero to three sub-points", .maximumCount(3))
    var subpoints: [String]
}

@Generable(description: "A table")
struct GeneratedTable {
    @Guide(description: "Column headings", .count(2...6))
    var columns: [String]
    var rows: [GeneratedRow]
}

@Generable
struct GeneratedRow {
    @Guide(description: "One cell per column, in order")
    var cells: [String]
}

@Generable(description: "Action items")
struct GeneratedTasks {
    var tasks: [String]
}

extension GeneratedOutline.PartiallyGenerated {
    var markdown: String {
        var lines: [String] = []
        if let heading, !heading.isEmpty { lines.append("## " + heading.trimmingCharacters(in: .whitespaces)) }
        let items = points ?? []
        if !items.isEmpty, !lines.isEmpty { lines.append("") }
        for point in items {
            guard let text = point.text, !text.isEmpty else { continue }
            lines.append("- " + MarkdownText.inline(text))
            for sub in point.subpoints ?? [] where !sub.isEmpty { lines.append("  - " + MarkdownText.inline(sub)) }
        }
        return lines.joined(separator: "\n")
    }
}

extension GeneratedTable.PartiallyGenerated {
    var markdown: String {
        let headers = (columns ?? []).filter { !$0.isEmpty }
        guard !headers.isEmpty else { return "" }
        let body = (rows ?? []).map { row in
            (0..<headers.count).map { index in index < (row.cells ?? []).count ? (row.cells ?? [])[index] : "" }
        }
        let cells = ([headers] + (body.isEmpty ? [Array(repeating: "", count: headers.count)] : body)).map { row in
            row.map { MarkdownText.inline($0).replacingOccurrences(of: "|", with: "\\|") }
        }
        return MarkdownTable(rows: cells).markdown
    }
}

extension GeneratedTasks.PartiallyGenerated {
    var markdown: String {
        (tasks ?? []).filter { !$0.isEmpty }.map { "- [ ] " + MarkdownText.inline($0) }.joined(separator: "\n")
    }
}

/// Keeps generated text on one line and out of markdown syntax it didn't mean.
enum MarkdownText {
    static func inline(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }
}
