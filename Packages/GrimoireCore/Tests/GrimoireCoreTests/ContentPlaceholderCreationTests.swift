import Darwin
import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct ContentPlaceholderCreationTests {
    @Test(arguments: [false, true])
    func allocatedTitlesPreserveUnicodeBeforeTheKnownExtension(_ collision: Bool) async throws {
        let scratch = try Scratch()
        let text = "{title}\r\n{title:yaml}\r{filename}\n{filename:yaml}"
        let (workspace, _) = try await scratch.workspace(files: ["source.md": text])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let source = folder.appending(path: "source.md")
        try workspace.assignTemplate(source, to: folder)
        let stem = "Draft\u{0D4E}"
        if collision { try scratch.file("notes/" + stem + ".md", "Competitor") }
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        guard case .published(let created) = workspace.createDocument(plan, naming: .edited(stem)) else {
            Issue.record("A valid literal Unicode stem must publish without rewriting")
            return
        }
        let expected =
            collision
            ? "Draft\u{0D4E} 2\r\n\"Draft\u{0D4E} 2\"\rDraft\u{0D4E} 2.md\n\"Draft\u{0D4E} 2.md\""
            : "Draft\u{0D4E}\r\n\"Draft\u{0D4E}\"\rDraft\u{0D4E}.md\n\"Draft\u{0D4E}.md\""
        #expect(created.url.lastPathComponent == (collision ? "Draft\u{0D4E} 2.md" : "Draft\u{0D4E}.md"))
        #expect(try Data(contentsOf: created.url) == Data(expected.utf8))
        #expect(created.editorCaretUTF16 == expected.utf16.count)
        #expect(try Data(contentsOf: source) == Data(text.utf8))
        if collision {
            #expect(try String(contentsOf: folder.appending(path: stem + ".md"), encoding: .utf8) == "Competitor")
        }
    }

    @Test(arguments: [
        (
            "{\r\n  \"title\": \"{title}\",\n  \"filename\": {filename:yaml}\r}\n",
            "{\r\n  \"title\": \"Draft\",\n  \"filename\": \"Draft.md\"\r}\n"
        ),
        (
            "unfinished {author then {title} and {filename:yaml} {title",
            "unfinished {author then Draft and \"Draft.md\" {title"
        ),
    ])
    func ordinaryBracesDoNotHideLaterExactPlaceholders(_ sourceText: String, _ expected: String) async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": sourceText])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let source = folder.appending(path: "source.md")
        try workspace.assignTemplate(source, to: folder)
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        guard case .published(let created) = workspace.createDocument(plan, naming: .generated) else {
            Issue.record("Ordinary braces must not prevent publication or expansion")
            return
        }
        #expect(try Data(contentsOf: created.url) == Data(expected.utf8))
        #expect(created.editorCaretUTF16 == expected.utf16.count)
        #expect(try Data(contentsOf: source) == Data(sourceText.utf8))
    }

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
        let renamed = try FileOperations.rename(created.url, to: "Renamed.md")
        let moved = try FileOperations.move(renamed, into: scratch.folder("notes/archive"))
        #expect(try Data(contentsOf: source) == snapshot)
        try Data("changed {title}".utf8).write(to: source)
        #expect(try Data(contentsOf: moved) == Data(expected.utf8))
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

    @Test func suffixRacesRegenerateFromOneSnapshotAndTimestampThroughTwoDigitSuffixes() async throws {
        let scratch = try Scratch()
        let text = "\u{feff}{title:yaml}\r\n{filename}\r{date} {time}  \n"
        let (workspace, _) = try await scratch.workspace(files: ["source.md": text])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let source = folder.appending(path: "source.md")
        try workspace.assignTemplate(source, to: folder)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 1_793_404_799)
        let plan = try workspace.prepareDocument(
            in: folder, filenamePattern: "{date} {time}", now: now, calendar: calendar)
        var operations = DocumentCreationOperations()
        var competitors: [URL] = []
        operations.publish = { directory, temporary, candidate in
            if competitors.count < 9 {
                let competitor = folder.appending(path: candidate)
                try Data("Competitor".utf8).write(to: competitor)
                competitors.append(competitor)
                try Data("next attempt {filename}".utf8).write(to: source)
            }
            try DocumentCreationOperations.publish(directory, temporary, candidate)
        }
        guard
            case .published(let created) = workspace.createDocument(
                plan, naming: .generated, now: now, calendar: calendar, operations: operations)
        else {
            Issue.record("Expected publication after competing creators")
            return
        }
        let expected = "\u{feff}\"2026-10-30 2359 10\"\r\n2026-10-30 2359 10.md\r2026-10-30 23:59:59  \n"
        #expect(created.url.lastPathComponent == "2026-10-30 2359 10.md")
        #expect(try Data(contentsOf: created.url) == Data(expected.utf8))
        #expect(created.editorCaretUTF16 == expected.utf16.count)
        for competitor in competitors { #expect(try Data(contentsOf: competitor) == Data("Competitor".utf8)) }
        #expect(try String(contentsOf: source, encoding: .utf8) == "next attempt {filename}")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 11)
    }

    @Test(arguments: [false, true])
    func visibleRetryRefreshesSavedContentAndTimeButPreservesNamingIntent(_ edited: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": "old {filename} {date} {time}"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let source = folder.appending(path: "source.md")
        try workspace.assignTemplate(source, to: folder)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let before = Date(timeIntervalSince1970: 1_793_404_799)
        let after = before.addingTimeInterval(2)
        let plan = try workspace.prepareDocument(
            in: folder, filenamePattern: "{date} {time}", now: before, calendar: calendar)
        let naming: DocumentNamingIntent = edited ? .edited("Keep {date} {time}") : .generated
        var operations = DocumentCreationOperations()
        operations.publish = { _, _, _ in throw POSIXError(.EACCES) }
        guard
            case .failed = workspace.createDocument(
                plan, naming: naming, now: before, calendar: calendar, operations: operations)
        else {
            Issue.record("First attempt must report the publication failure")
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["source.md"])
        try Data("new {filename} {date} {time}".utf8).write(to: source)
        guard
            case .published(let created) = workspace.createDocument(
                plan, naming: naming, now: after, calendar: calendar, operations: DocumentCreationOperations())
        else {
            Issue.record("A user-visible retry must start a fresh attempt")
            return
        }
        let filename = edited ? "Keep {date} {time}.md" : "2026-10-31 0000.md"
        #expect(created.url.lastPathComponent == filename)
        #expect(try String(contentsOf: created.url, encoding: .utf8) == "new \(filename) 2026-10-31 00:00:01")
    }
}
