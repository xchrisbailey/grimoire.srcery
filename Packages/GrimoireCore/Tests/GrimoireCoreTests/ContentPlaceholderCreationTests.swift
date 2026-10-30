import Darwin
import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct ContentPlaceholderCreationTests {
    @Test func yamlStringsAndLiteralEscapesExpandOnceWithoutReserializing() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let source = folder.appending(path: "source.md")
        try workspace.assignTemplate(source, to: folder)
        let text = [
            "\u{feff}---\r\ntitle: {title:yaml}\rfilename: {filename:yaml}\n",
            "date: {date:yaml}\r\ntime: {time:yaml}\r---\n",
            "{title}|{filename}|{date}|{time}\r\n",
            "{{title}} {{filename}} {{date}} {{time}}\n",
            "{{title:yaml}} {{filename:yaml}} {{date:yaml}} {{time:yaml}}\r",
            "{Title} {FILENAME} {author} {title:other} {title:YAML} {date:yaml:other}\n",
            "\"{title:yaml}\"  \t\r\n{title",
        ].joined()
        let snapshot = Data(text.utf8)
        try snapshot.write(to: source)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 3600))
        let now = Date(timeIntervalSince1970: 1_793_404_745)
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft", now: now, calendar: calendar)
        guard
            case .published(let created) = workspace.createDocument(
                plan, naming: .edited("Élan: \"{date}\" 🧙.v1"), now: now, calendar: calendar,
                operations: DocumentCreationOperations())
        else {
            Issue.record("Expected expanded document")
            return
        }
        let expected = [
            "\u{feff}---\r\ntitle: \"Élan: \\\"{date}\\\" 🧙.v1\"\r",
            "filename: \"Élan: \\\"{date}\\\" 🧙.v1.md\"\n",
            "date: \"2026-10-31\"\r\ntime: \"00:59:05\"\r---\n",
            "Élan: \"{date}\" 🧙.v1|Élan: \"{date}\" 🧙.v1.md|2026-10-31|00:59:05\r\n",
            "{title} {filename} {date} {time}\n",
            "{title:yaml} {filename:yaml} {date:yaml} {time:yaml}\r",
            "{Title} {FILENAME} {author} {title:other} {title:YAML} {date:yaml:other}\n",
            "\"\"Élan: \\\"{date}\\\" 🧙.v1\"\"  \t\r\n{title",
        ].joined()
        #expect(created.url.lastPathComponent == "Élan: \"{date}\" 🧙.v1.md")
        #expect(try Data(contentsOf: created.url) == Data(expected.utf8))
        #expect(created.editorCaretUTF16 == expected.utf16.count)
        #expect(try Data(contentsOf: source) == snapshot)
    }

    @Test func yamlEscapesGeneratedFilenameBackslashesControlsAndLineBreaks() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": "{title:yaml}\n{filename:yaml}"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(folder.appending(path: "source.md"), to: folder)
        let stem = "a\"\\\t\n\r\u{1}\u{7f}\u{85}\u{2028}\u{2029}🧙z"
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: stem)
        guard case .published(let created) = workspace.createDocument(plan, naming: .generated) else {
            Issue.record("Generated names retain existing filename-pattern sanitization")
            return
        }
        let escaped = "a\\\"\\\\\\u0009\\u000A\\u000D\\u0001\\u007F\\u0085\\u2028\\u2029🧙z"
        let expected = "\"" + escaped + "\"\n\"" + escaped + ".md\""
        #expect(created.url.lastPathComponent == stem + ".md")
        #expect(try Data(contentsOf: created.url) == Data(expected.utf8))
        #expect(created.editorCaretUTF16 == expected.utf16.count)
    }
}
