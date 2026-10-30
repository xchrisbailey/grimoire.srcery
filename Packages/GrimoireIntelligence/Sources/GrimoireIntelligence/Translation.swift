import Foundation
import GrimoireCore

enum TranslationSource {
    static func validateReferences(in source: String) throws {
        let index = BlockIndex(text: source)
        for block in index.blocks {
            switch block.kind {
            case .codeBlock: continue
            case .linkDefinitions: throw IntelligenceError.unsupportedTranslationSource
            default: break
            }
            let text = block.source as NSString
            var protected = Set<Int>()
            for span in InlineScanner.scan(block.source) {
                let ranges: [Range<Int>]
                switch span.kind {
                case .code, .autolink, .image: ranges = [span.range]
                default: ranges = span.markers
                }
                for range in ranges { protected.formUnion(range) }
            }
            if case .listItem = block.kind {
                protected.formUnion(0..<MarkdownSyntax.listPrefix(in: block.source).length)
            }
            // Unclaimed brackets may be reference IDs, even when their definition is outside
            // the selection. Refuse ambiguous syntax instead of translating structural text.
            for offset in 0..<text.length where !protected.contains(offset) {
                if text.character(at: offset) == 91 || text.character(at: offset) == 93 {
                    throw IntelligenceError.unsupportedTranslationSource
                }
            }
        }
    }
}
