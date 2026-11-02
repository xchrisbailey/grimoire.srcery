import Darwin
import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite(.mainActorGate) struct AssignedDocumentCreationTests {
    @Test(arguments: ["", " ", " name", "name ", ".", "..", ".hidden", "a/b", "a\\b", "a\n", "a\0b", "a\u{7f}b"])
    func invalidLiteralNamesAndCancellationHaveNoSideEffects(_ name: String) async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": "static"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(folder.appending(path: "source.md"), to: folder)
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        guard case .cancelled = workspace.createDocument(plan, naming: .edited(name), confirmed: false) else {
            Issue.record("Cancellation must not validate or create")
            return
        }
        guard case .invalidName = workspace.createDocument(plan, naming: .edited(name)) else {
            Issue.record("Invalid literal stem must fail visibly")
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["source.md"])
    }

    @Test func changedAssignmentRequiresReviewButUnrelatedProjectEditsDoNot() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["first.md": "first", "second.md": "second"])
        let other = Workspace(projectID: workspace.projectID, library: library)
        other.activate()
        defer { workspace.deactivate(); other.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(folder.appending(path: "first.md"), to: folder)
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        try other.assignTemplate(folder.appending(path: "second.md"), to: folder)
        guard case .reviewNeeded(let updated) = workspace.createDocument(plan, naming: .edited("My : {date} 🧙")) else {
            Issue.record("Changed source identity needs review before any write")
            return
        }
        #expect(updated.source?.lastPathComponent == "second.md")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
        try library.update(workspace.projectID) { $0.name = "Unrelated rename" }
        guard case .published(let created) = workspace.createDocument(updated, naming: .edited("My : {date} 🧙")) else {
            Issue.record("Unrelated edits must not require another review")
            return
        }
        #expect(created.url.lastPathComponent == "My : {date} 🧙.md")
        #expect(try String(contentsOf: created.url, encoding: .utf8) == "second")
    }

    @Test func replacementDestinationRequiresReviewAndKeepsTheEnteredName() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let folder = try scratch.folder("notes/posts")
        try workspace.assignTemplate(scratch.url.appending(path: "notes/source.md"), to: folder)
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        try FileManager.default.moveItem(at: folder, to: scratch.url.appending(path: "notes/old"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        guard case .reviewNeeded(let updated) = workspace.createDocument(plan, naming: .edited("Keep me")) else {
            Issue.record("Replacement folder must need review")
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        guard case .published(let created) = workspace.createDocument(updated, naming: .edited("Keep me")) else {
            Issue.record("Reviewed details should permit creation")
            return
        }
        #expect(created.url.lastPathComponent == "Keep me.md")
    }

    @Test func authoritativeRegrantInAnotherWindowDoesNotWriteThroughStaleFolders() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let root = try #require(workspace.folders.first?.id)
        try workspace.assignTemplate(folder.appending(path: "source.md"), to: folder)
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        let replacement = try scratch.folder("replacement")
        try library.replaceBookmark(of: root, in: workspace.projectID, with: replacement)
        guard case .contextUnavailable = workspace.createDocument(plan, naming: .edited("Keep me")) else {
            Issue.record("A destination outside the current binding must stop")
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["source.md"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: replacement.path).isEmpty)
    }

    @Test(arguments: [Data(), Data([0xef, 0xbb, 0xbf]), Data("a\r\nb\rc  ".utf8)])
    func eligibleSavedTextIsPreservedExactly(_ bytes: Data) async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": "initial"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let source = folder.appending(path: "source.md")
        try workspace.assignTemplate(source, to: folder)
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        try bytes.write(to: source)
        guard case .published(let created) = workspace.createDocument(plan, naming: .generated) else {
            Issue.record("Empty and unusual UTF-8 sources are valid")
            return
        }
        #expect(try Data(contentsOf: created.url) == bytes)
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test(arguments: [Data([0xff]), Data([0xc0, 0xaf]), Data([0x61, 0, 0x62])])
    func unsupportedSavedTextFailsClosedWithoutChangingAssignments(_ bytes: Data) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "initial"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let source = folder.appending(path: "source.md")
        try workspace.assignTemplate(source, to: folder)
        let before = library.projects
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        try bytes.write(to: source)
        guard case .sourceFailure(_, let error) = workspace.createDocument(plan, naming: .generated) else {
            Issue.record("Unsupported saved bytes must stop creation")
            return
        }
        #expect(error is TemplateAssignmentError)
        #expect(try Data(contentsOf: source) == bytes)
        #expect(library.projects == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["source.md"])
    }

    @Test func missingExplicitSourceNeverFallsBackAndCancellationDoesNotMakeSubfolders() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": "initial"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let source = folder.appending(path: "source.md")
        try workspace.assignTemplate(source, to: folder)
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        try FileManager.default.removeItem(at: source)
        guard case .sourceFailure = workspace.createDocument(plan, naming: .generated) else {
            Issue.record("Missing explicit source must fail closed")
            return
        }
        let missing = folder.appending(path: "not/made")
        let cancelled = try workspace.prepareDocument(in: missing, filenamePattern: "Draft")
        #expect(cancelled.requiresNaming)
        guard case .cancelled = workspace.createDocument(cancelled, naming: .generated, confirmed: false) else {
            Issue.record("Expected cancellation")
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func collisionLoopRetainsOneSavedSnapshotAndPreservesCompetitors() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": "first {filename}"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let source = folder.appending(path: "source.md")
        try workspace.assignTemplate(source, to: folder)
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        var operations = DocumentCreationOperations()
        operations.publish = { directory, temporary, candidate in
            if candidate == "Draft.md" {
                try Data("live edit".utf8).write(to: source)
                try scratch.file("notes/Draft.md", "Competitor")
            }
            try DocumentCreationOperations.publish(directory, temporary, candidate)
        }
        guard
            case .published(let created) = workspace.createDocument(
                plan, naming: .generated, now: .now, calendar: .current, operations: operations)
        else {
            Issue.record("Expected collision-safe publication")
            return
        }
        #expect(created.url.lastPathComponent == "Draft 2.md")
        #expect(try String(contentsOf: created.url, encoding: .utf8) == "first Draft 2.md")
        #expect(created.editorCaretUTF16 == 16)
        #expect(try String(contentsOf: folder.appending(path: "Draft.md"), encoding: .utf8) == "Competitor")
        #expect(try String(contentsOf: source, encoding: .utf8) == "live edit")
    }

    @Test(arguments: [POSIXErrorCode.ENOSPC, .EACCES, .ENOTSUP])
    func outputFailureLeavesOnlyTheSourceAndCanRetrySafely(_ code: POSIXErrorCode) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(folder.appending(path: "source.md"), to: folder)
        let before = library.projects
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        var operations = DocumentCreationOperations()
        operations.publish = { _, _, _ in throw POSIXError(code) }
        guard
            case .failed = workspace.createDocument(
                plan, naming: .generated, now: .now, calendar: .current, operations: operations)
        else {
            Issue.record("Failed publication must not hand off a document")
            return
        }
        #expect(library.projects == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["source.md"])
        guard case .published = workspace.createDocument(plan, naming: .generated) else {
            Issue.record("A failed publication may be retried without duplicates")
            return
        }
    }

}

extension AssignedDocumentCreationTests {
    @Test func reviewingAnOptOutKeepsTheNamedEditorHandoffInsteadOfFallingIntoLegacyCreation() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(folder.appending(path: "source.md"), to: folder)
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        let assignment = try #require(plan.assignment)
        try library.update(workspace.projectID) {
            $0.templateAssignments = [FolderTemplateAssignment(owner: assignment.owner, choice: .noTemplate)]
        }
        guard case .reviewNeeded(let updated) = workspace.createDocument(plan, naming: .edited("Keep me")) else {
            Issue.record("A changed opt-out requires review")
            return
        }
        guard case .published(let created) = workspace.createDocument(updated, naming: .edited("Keep me")) else {
            Issue.record("The reviewed opt-out should publish empty content")
            return
        }
        #expect(created.editorCaretUTF16 == 0)
        #expect(created.url.lastPathComponent == "Keep me.md")
        #expect(try Data(contentsOf: created.url).isEmpty)
        guard case .alreadyPublished = workspace.createDocument(plan, naming: .edited("Keep me")) else {
            Issue.record("Review must keep one pending creation identity")
            return
        }
    }

    @Test func generatedNamesRefreshAtConfirmationWhileEditedNamesStayLiteral() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": "{date} {time}"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(folder.appending(path: "source.md"), to: folder)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let beforeMidnight = Date(timeIntervalSince1970: 1_793_404_740)
        let afterMidnight = beforeMidnight.addingTimeInterval(120)
        let generated = try workspace.prepareDocument(
            in: folder, filenamePattern: "{date} {time}", now: beforeMidnight, calendar: calendar)
        #expect(generated.suggestedStem == "2026-10-30 2359")
        guard
            case .published(let refreshed) = workspace.createDocument(
                generated, naming: .generated, now: afterMidnight, calendar: calendar,
                operations: DocumentCreationOperations())
        else {
            Issue.record("Expected refreshed suggestion")
            return
        }
        #expect(refreshed.url.lastPathComponent == "2026-10-31 0001.md")
        #expect(try String(contentsOf: refreshed.url, encoding: .utf8) == "2026-10-31 00:01:00")
        let edited = try workspace.prepareDocument(
            in: folder, filenamePattern: "{date}", now: beforeMidnight, calendar: calendar)
        guard
            case .published(let literal) = workspace.createDocument(
                edited, naming: .edited("{date}: a.b"), now: afterMidnight, calendar: calendar,
                operations: DocumentCreationOperations())
        else {
            Issue.record("Expected literal typed name")
            return
        }
        #expect(literal.url.lastPathComponent == "{date}: a.b.md")
        #expect(try String(contentsOf: literal.url, encoding: .utf8) == "2026-10-31 00:01:00")
    }

    @Test func inheritedLookupNamesDescendantsAndAuthoringBypassesAssignments() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(folder.appending(path: "source.md"), to: folder)
        let child = try scratch.folder("notes/child")
        let plan = try workspace.prepareDocument(in: child, filenamePattern: "Legacy")
        #expect(plan.requiresNaming)
        guard case .published(let legacy) = workspace.createDocument(plan, naming: .generated) else {
            Issue.record("A descendant must inherit its ancestor's saved source")
            return
        }
        #expect(legacy.editorCaretUTF16 == 5)
        #expect(try String(contentsOf: legacy.url, encoding: .utf8) == "saved")
        let authoring = try workspace.prepareDocument(in: folder, filenamePattern: "Author", purpose: .templateSource)
        #expect(!authoring.requiresNaming)
        guard case .published(let source) = workspace.createDocument(authoring, naming: .generated) else {
            Issue.record("Explicit authoring purpose bypasses the assignment")
            return
        }
        #expect(try Data(contentsOf: source.url).isEmpty)
        let assignment = try #require(try workspace.templateAssignment(for: folder))
        try library.update(workspace.projectID) {
            $0.templateAssignments = [FolderTemplateAssignment(owner: assignment.owner, choice: .noTemplate)]
        }
        #expect(try !workspace.prepareDocument(in: folder, filenamePattern: "Opt out").requiresNaming)
        try library.update(workspace.projectID) {
            var inactive = assignment
            inactive.state = .unresolved
            $0.templateAssignments = [inactive]
        }
        #expect(try !workspace.prepareDocument(in: folder, filenamePattern: "Inactive").requiresNaming)
    }

    @Test func sourceAccessLossBeforePublicationFailsWithoutFinalOutput() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let source = folder.appending(path: "source.md")
        try workspace.assignTemplate(source, to: folder)
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        var operations = DocumentCreationOperations()
        operations.write = { _ in try FileManager.default.removeItem(at: source) }
        guard
            case .failed = workspace.createDocument(
                plan, naming: .generated, now: .now, calendar: .current, operations: operations)
        else {
            Issue.record("Lost source access must stop publication")
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func postPublicationContextFailureCannotRetryOrDeletePublishedContent() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let source = folder.appending(path: "source.md")
        try workspace.assignTemplate(source, to: folder)
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        var operations = DocumentCreationOperations()
        operations.publish = { directory, temporary, candidate in
            try DocumentCreationOperations.publish(directory, temporary, candidate)
            try FileManager.default.removeItem(at: source)
        }
        guard
            case .publishedButUnavailable(let url) = workspace.createDocument(
                plan, naming: .generated, now: .now, calendar: .current, operations: operations)
        else {
            Issue.record("Postpublication failure is not a creation failure")
            return
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "saved")
        guard case .alreadyPublished = workspace.createDocument(plan, naming: .generated) else {
            Issue.record("Published output must not be retried")
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Draft.md"])
    }

    @Test(arguments: [DocumentRecoveryIntent.retry, .createEmptyOnce])
    func facadeExhaustionPreservesAll32CompetitorsAndCleansTemporaryOutput(_ recovery: DocumentRecoveryIntent)
        async throws
    {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(folder.appending(path: "source.md"), to: folder)
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        var operations = DocumentCreationOperations()
        var attempts = 0
        operations.publish = { directory, temporary, candidate in
            attempts += 1
            if attempts <= 32 { try scratch.file("notes/" + candidate, "Competitor") }
            try DocumentCreationOperations.publish(directory, temporary, candidate)
        }
        guard
            case .failed = workspace.createDocument(
                plan, naming: .generated, recovery: recovery, now: .now, calendar: .current, operations: operations)
        else {
            Issue.record("The 33rd publication must not be attempted")
            return
        }
        #expect(attempts == 32)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.count == 33)
        #expect(!names.contains { $0.hasPrefix(".grimoire-create-") })
        #expect(try String(contentsOf: folder.appending(path: "Draft 32.md"), encoding: .utf8) == "Competitor")
    }
}
