import Foundation
import FoundationModels
import GrimoireCore

@Generable(description: "Translated prose pieces, in the same order as the input pieces")
struct GeneratedTranslation {
    @Guide(description: "One plain prose translation per input piece, with no Markdown or added commentary")
    var pieces: [String]
}

extension GeneratedTranslation.PartiallyGenerated {
    func markdown(source: String) throws -> String {
        try markdown(in: TranslationSource(source))
    }

    func markdown(in source: TranslationSource) throws -> String {
        guard let pieces, pieces.count == source.ranges.count else { throw IntelligenceError.invalidTranslation }
        let translated = try pieces.map { piece in
            let text = piece.trimmingCharacters(in: .whitespaces)
            guard text.contains(where: \.isLetter), !text.contains(where: \.isNewline),
                !text.contains(where: { "[]`*_~<>|#\\".contains($0) }), InlineScanner.scan(text).isEmpty
            else { throw IntelligenceError.invalidTranslation }
            // Generated fields are prose, not syntax. Escape punctuation that could join
            // adjacent source markers or introduce a new block or HTML entity.
            return text.map { "!(){}+-.&".contains($0) ? "\\" + String($0) : String($0) }.joined()
        }
        let original = source.source as NSString
        var result = ""
        var cursor = 0
        for (range, text) in zip(source.ranges, translated) {
            result += original.substring(with: NSRange(location: cursor, length: range.lowerBound - cursor))
            result += text
            cursor = range.upperBound
        }
        return result + original.substring(from: cursor)
    }
}

struct TranslationSource {
    let source: String
    let ranges: [Range<Int>]

    var pieces: [String] { ranges.map { (source as NSString).substring(with: NSRange($0)) } }

    init(_ source: String) throws {
        self.source = source
        let index = BlockIndex(text: source)
        var ranges: [Range<Int>] = []
        for (position, block) in index.blocks.enumerated() {
            let local = try Self.proseRanges(in: block)
            ranges += local.map { (index.starts[position] + $0.lowerBound)..<(index.starts[position] + $0.upperBound) }
        }
        self.ranges = ranges
    }

    private static func proseRanges(in block: Block) throws -> [Range<Int>] {
        switch block.kind {
        case .codeBlock, .thematicBreak, .html, .mdx: return []
        case .linkDefinitions:
            // The block parser also uses this kind for source gaps such as closing
            // heading hashes. Keep those bytes opaque, but refuse possible reference IDs.
            if block.source.contains("[") || block.source.contains("]") {
                throw IntelligenceError.unsupportedTranslationSource
            }
            return []
        case .blockquote, .listItem: return try containerRanges(in: block)
        default: break
        }
        let text = block.source as NSString
        let protected = try protectedOffsets(in: block)
        var ranges: [Range<Int>] = []
        var cursor = 0
        while cursor < text.length {
            if protected.contains(cursor) { cursor += 1; continue }
            let start = cursor
            while cursor < text.length, !protected.contains(cursor) { cursor += 1 }
            let value = text.substring(with: NSRange(start..<cursor))
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains(where: \.isLetter) else { continue }
            let leading = value.prefix(while: \.isWhitespace).utf16.count
            ranges.append((start + leading)..<(start + leading + trimmed.utf16.count))
        }
        return ranges
    }

    private static func inlineProtection(in source: String) -> Set<Int> {
        var protected = Set<Int>()
        for span in InlineScanner.scan(source) {
            switch span.kind {
            case .code, .autolink: protected.formUnion(span.range)
            default:
                for marker in span.markers { protected.formUnion(marker) }
            }
        }
        let utf16 = Array(source.utf16)
        let punctuation = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".utf16)
        var escaped = 0
        while escaped + 1 < utf16.count {
            if utf16[escaped] == 92, punctuation.contains(utf16[escaped + 1]) {
                protected.formUnion(escaped..<(escaped + 2))
                escaped += 2
            } else {
                escaped += 1
            }
        }
        // Keep unmatched delimiters and hard-break backslashes source-backed too;
        // the scanner deliberately reports only matched inline spans.
        let delimiters = Set("\\`*_~#".utf16)
        for offset in utf16.indices where delimiters.contains(utf16[offset]) { protected.insert(offset) }
        return protected
    }

    private static func protectedOffsets(in block: Block) throws -> Set<Int> {
        let text = block.source as NSString
        var protected = inlineProtection(in: block.source)
        var cursor = 0
        var lines: [Range<Int>] = []
        while cursor < text.length {
            var end = 0
            var contentsEnd = 0
            text.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: cursor, length: 0))
            lines.append(cursor..<contentsEnd)
            protected.formUnion(contentsEnd..<end)
            cursor = end
        }
        if case .heading = block.kind, let first = lines.first {
            if lines.count > 1, let last = lines.last {
                protected.formUnion(last)
            } else {
                let markers = MarkdownSyntax.headingMarkers(in: text.substring(with: NSRange(first)))
                protected.formUnion(first.lowerBound..<(first.lowerBound + markers.prefix))
                protected.formUnion((first.lowerBound + markers.suffixStart)..<first.upperBound)
            }
        }
        if case .table = block.kind {
            for offset in 0..<text.length where text.character(at: offset) == 124 { protected.insert(offset) }
        }
        // Unclaimed brackets may be reference IDs, even when their definition is outside
        // the selection. Refuse ambiguous syntax instead of translating structural text.
        for offset in 0..<text.length where !protected.contains(offset) {
            if text.character(at: offset) == 91 || text.character(at: offset) == 93 {
                throw IntelligenceError.unsupportedTranslationSource
            }
        }
        return protected
    }

    private static func containerRanges(in block: Block) throws -> [Range<Int>] {
        let source = block.source as NSString
        let prefix = MarkdownSyntax.listPrefix(in: block.source)
        var content = ""
        var offsets: [Int] = []
        var cursor = 0
        while cursor < source.length {
            var end = 0
            var contentsEnd = 0
            source.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: cursor, length: 0))
            let line = source.substring(with: NSRange(cursor..<contentsEnd))
            let width: Int
            if case .blockquote = block.kind {
                width = MarkdownSyntax.quoteMarker(in: line)
            } else if cursor == 0 {
                width = prefix.length
            } else {
                width = line.prefix { $0 == " " }.prefix(prefix.indent + prefix.marker).utf16.count
            }
            let range = (cursor + width)..<end
            content += source.substring(with: NSRange(range))
            offsets.append(contentsOf: range)
            cursor = end
        }
        // Parse container contents with the existing block model, so indented/fenced code
        // inside lists and quotes stays opaque. Map prose back without rewriting prefixes.
        return try TranslationSource(content).ranges.map { range in
            offsets[range.lowerBound]..<(offsets[range.upperBound - 1] + 1)
        }
    }
}

@MainActor
extension IntelligenceService {
    func translate(_ source: String, into language: String) -> AsyncThrowingStream<String, Error> {
        guard !Task.isCancelled else { return AsyncThrowingStream { $0.finish() } }
        let projection: TranslationSource
        do { projection = try TranslationSource(source) } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        guard !projection.ranges.isEmpty else {
            return AsyncThrowingStream {
                $0.yield(source); $0.finish()
            }
        }
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let task = Task { @MainActor in
            do {
                try Task.checkCancellation()
                let pieces = try String(decoding: JSONEncoder().encode(projection.pieces), as: UTF8.self)
                let request = IntelligenceRequest(
                    instructions: Prompts.translate(into: language),
                    text:
                        "Original passage (context only):\n\(source)\n\nProse pieces to translate in order:\n\(pieces)")
                var lastSafe = source
                var failure: Error? = IntelligenceError.invalidTranslation
                let generated = streamGenerated(GeneratedTranslation.self, for: request) { snapshot in
                    do {
                        lastSafe = try snapshot.markdown(in: projection)
                        failure = nil
                    } catch { failure = error }
                    return lastSafe
                }
                for try await snapshot in generated {
                    try Task.checkCancellation()
                    continuation.yield(snapshot)
                }
                try Task.checkCancellation()
                if let failure { throw failure }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}
