import Foundation
import Testing

@testable import GrimoireCore

@Suite struct PerformanceTests {
    /// About 1 MB of mixed markdown built from the README corpus.
    static let megabyte: String = {
        let readmes = (try? Corpus.files(in: "readmes").map { try Corpus.text($0) }) ?? []
        var text = ""
        while text.utf8.count < 1_000_000 {
            for readme in readmes { text += readme + "\n" }
        }
        return text
    }()

    #if DEBUG
    static let budget = Duration.milliseconds(500)
    #else
    /// The target from #3: a 1 MB parse in about 50 ms on Apple silicon.
    static let budget = Duration.milliseconds(50)
    #endif

    @Test func parseOneMegabyte() {
        let text = Self.megabyte
        _ = Document(parsing: text)  // warm up
        let clock = ContinuousClock()
        let elapsed = (0..<5).map { _ in clock.measure { _ = Document(parsing: text) } }.min()!
        print("Parsed \(text.utf8.count) bytes in \(elapsed)")
        #expect(elapsed < Self.budget)
    }

    @Test func editedBlockReparsesQuickly() {
        var document = Document(parsing: Self.megabyte)
        let index = document.blocks.count / 2
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            document.replaceSource(at: index, with: "An edited paragraph.")
        }
        #expect(elapsed < .milliseconds(5))
    }

    /// Typing a character in the middle of a 1 MB document re-parses only nearby blocks.
    @Test func typingUpdatesTheIndexQuickly() {
        let text = Self.megabyte
        var index = BlockIndex(text: text)
        let middle = index.sourceRange(of: index.blocks.count / 2).lowerBound
        let edited = (text as NSString).replacingCharacters(in: NSRange(location: middle, length: 0), with: "x")
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            index.replace(middle..<middle, replacementLength: 1, in: edited)
        }
        #expect(index.document.markdown == edited)
        #expect(elapsed < .milliseconds(5))
    }
}
