#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import GrimoireIntelligence

/// Draws `lines` (a title, then rows of tab-separated cells) as a screenshot-like image.
@MainActor func renderedTable(title: String, rows: [[String]]) -> CGImage {
    let size = CGSize(width: 900, height: 120 + rows.count * 56)
    let image = NSImage(size: size, flipped: true) { rect in
        NSColor.white.setFill()
        rect.fill()
        let titleFont = NSFont.boldSystemFont(ofSize: 34)
        (title as NSString).draw(at: CGPoint(x: 40, y: 24), withAttributes: [.font: titleFont])
        let font = NSFont.systemFont(ofSize: 24)
        for (row, cells) in rows.enumerated() {
            let y = 100 + CGFloat(row) * 56
            NSColor.gray.setStroke()
            NSBezierPath.strokeLine(from: CGPoint(x: 30, y: y - 8), to: CGPoint(x: 870, y: y - 8))
            for (column, cell) in cells.enumerated() {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: row == 0 ? NSFont.boldSystemFont(ofSize: 24) : font
                ]
                (cell as NSString).draw(at: CGPoint(x: 40 + CGFloat(column) * 280, y: y), withAttributes: attributes)
            }
        }
        NSBezierPath.strokeLine(
            from: CGPoint(x: 30, y: 100 + CGFloat(rows.count) * 56 - 8),
            to: CGPoint(x: 870, y: 100 + CGFloat(rows.count) * 56 - 8))
        return true
    }
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
}

/// A plain picture with no text: a red circle on a blue square.
@MainActor func renderedShapes() -> CGImage {
    let image = NSImage(size: CGSize(width: 400, height: 400), flipped: false) { rect in
        NSColor.systemBlue.setFill()
        rect.fill()
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 100, dy: 100)).fill()
        return true
    }
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
}

/// A slide: a big title and a few lines with no markers.
@MainActor func renderedSlide(title: String, lines: [String]) -> CGImage {
    let image = NSImage(size: CGSize(width: 1000, height: 600), flipped: true) { rect in
        NSColor.white.setFill()
        rect.fill()
        (title as NSString).draw(at: CGPoint(x: 60, y: 50), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 54)])
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(
                at: CGPoint(x: 80, y: 180 + CGFloat(index) * 70), withAttributes: [.font: NSFont.systemFont(ofSize: 36)]
            )
        }
        return true
    }
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
}

let potionRows = [
    ["Potion", "Ingredient", "Steep"], ["Ember", "Cinnamon", "3 days"], ["Moonwater", "Silver leaf", "12 nights"],
    ["Hearth", "Rosemary", "1 hour"],
]

@MainActor @Suite struct ImageTextTests {
    @Test func readsATableScreenshot() async throws {
        let draft = try await ImageText.draft(of: renderedTable(title: "Potions", rows: potionRows))
        print("DRAFT:\n\(draft)")
        for word in ["Potions", "Ember", "Moonwater", "Silver leaf", "12 nights", "Rosemary"] {
            #expect(draft.contains(word))
        }
    }

    @Test func aSlideWithoutStructureGoesToTheModel() {
        #expect(!ImageText.hasStructure("## Notes\n\nBuy ink and quills."))
        #expect(ImageText.hasStructure("Notes\n\n- ink\n- quills"))
        #expect(ImageText.hasStructure("| a | b |\n| - | - |"))
    }

    @Test func altTextIsOnePlainSentence() {
        #expect(IntelligenceService.altText("\"An image of a red circle on blue.\"") == "A red circle on blue")
        #expect(IntelligenceService.altText("A [draft] note.\nSecond line.") == "A (draft) note. Second line")
    }

    @Test func keepsTheTextChecksWords() {
        #expect(IntelligenceService.keepsTheText("| Ember | 3 days |", of: "Ember 3 days"))
        #expect(!IntelligenceService.keepsTheText("A table of potions", of: "Ember 3 days Moonwater"))
    }
}

/// The "done when" for #20, on the real model.
@MainActor @Suite(.enabled(if: modelIsReady), .serialized) struct ImageEvaluations {
    @Test func aTableScreenshotBecomesATable() async throws {
        let markdown = try await IntelligenceService.shared.markdown(
            from: renderedTable(title: "Potions", rows: potionRows))
        print("EVAL image table:\n\(markdown)")
        let lines = markdown.components(separatedBy: "\n")
        #expect(lines.first == "## Potions")
        #expect(lines.contains("| Potion    | Ingredient  | Steep     |"))
        #expect(lines.contains { $0.hasPrefix("|") && $0.contains("Moonwater") && $0.contains("12 nights") })
        #expect(lines.contains { $0.range(of: #"^\|\s*:?-+"#, options: .regularExpression) != nil })
    }

    @Test func aSlideBecomesAHeadingAndPoints() async throws {
        let lines = ["Brew the ember tonic", "Label every jar", "Clean the cauldron"]
        let image = renderedSlide(title: "Friday Tasks", lines: lines)
        print("EVAL slide draft:\n\(try await ImageText.draft(of: image))")
        let markdown = try await IntelligenceService.shared.markdown(from: image)
        print("EVAL slide:\n\(markdown)")
        #expect(markdown.contains("# Friday Tasks"))
        for line in lines { #expect(markdown.contains(line)) }
    }

    @Test func picturesGetSensibleAltText() async throws {
        let alt = try await IntelligenceService.shared.describeImage(renderedShapes())
        print("EVAL alt: \(alt)")
        #expect(!alt.isEmpty && alt.count < 140)
        #expect(!alt.contains("\n") && !alt.contains("["))
        #expect(alt.lowercased().contains("circle") || alt.lowercased().contains("red"))
    }

    @Test func screenshotsAreDescribedToo() async throws {
        let alt = try await IntelligenceService.shared.describeImage(
            renderedTable(title: "Potions", rows: potionRows))
        print("EVAL alt table: \(alt)")
        #expect(!alt.isEmpty && alt.count < 140)
    }
}
#endif
