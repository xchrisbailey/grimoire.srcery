import Darwin
import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct DocumentRecoveryTests {
    enum SourceLoss: CaseIterable { case missing, inaccessible, outsideLink }

    @Test(arguments: SourceLoss.allCases)
    func brokenNearerSourceNeverUsesAncestorAndInvalidReplacementNeverCommits(_ loss: SourceLoss) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["ancestor.md": "ancestor", "source.md": "saved"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let child = try scratch.folder("notes/child")
        let source = root.appending(path: "source.md")
        let outside = try scratch.file("outside.md", "outside")
        try workspace.assignTemplate(root.appending(path: "ancestor.md"), to: root)
        try workspace.assignTemplate(source, to: child)
        let plan = try workspace.prepareDocument(in: child, filenamePattern: "Draft")
        let before = library.projects
        switch loss {
        case .missing:
            try FileManager.default.removeItem(at: source)
        case .inaccessible:
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.path)
        case .outsideLink:
            try FileManager.default.removeItem(at: source)
            try FileManager.default.createSymbolicLink(at: source, withDestinationURL: outside)
        }
        defer {
            if loss == .inaccessible {
                do {
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
                } catch { Issue.record(error) }
            }
        }
        guard case .sourceFailure(let blocked, let error) = workspace.createDocument(plan, naming: .edited("Keep me"))
        else {
            Issue.record("Broken explicit source must not use an ancestor, cached bytes or empty content")
            return
        }
        #expect(blocked.assignment == plan.assignment)
        #expect(blocked.source == plan.source)
        #expect(blocked.source?.lastPathComponent == "source.md")
        #expect(!error.localizedDescription.isEmpty)
        guard case .failed = workspace.repairDocumentTemplate(plan, replacement: outside) else {
            Issue.record("Outside-project replacement must not commit")
            return
        }
        guard case .cancelled = workspace.createDocument(plan, naming: .edited("Keep me"), confirmed: false) else {
            Issue.record("Recovery cancellation must not create output")
            return
        }
        #expect(library.projects == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).isEmpty)
        #expect(try Data(contentsOf: outside) == Data("outside".utf8))
    }

    @Test func inaccessibleSourceRootStillIdentifiesBrokenReferenceAndAllowsExplicitRecovery() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["replacement.md": "replacement"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let templates = try scratch.folder("templates")
        let source = try scratch.file("templates/source.md", "saved")
        let binding = try library.bindFolder(templates, to: workspace.projectID)
        workspace.sync()
        try workspace.assignTemplate(source, to: root)
        let assignment = try workspace.templateAssignment(for: root)
        let index = try #require(library.project(workspace.projectID)?.roots.firstIndex(where: { $0.id == binding.id }))
        try library.update(workspace.projectID) { project in
            project.roots[index].bookmark = Data([0xff])
        }
        let plan = try workspace.prepareDocument(in: root, filenamePattern: "Draft")
        #expect(plan.source == nil)
        #expect(plan.assignment == assignment)
        guard case .sourceFailure(let blocked, _) = workspace.createDocument(plan, naming: .edited("Keep me")) else {
            Issue.record("Missing live root access is a source failure, not permission for empty fallback")
            return
        }
        #expect(blocked.assignment == assignment)
        guard
            case .cancelled = workspace.repairDocumentTemplate(
                plan, replacement: root.appending(path: "replacement.md"), confirmed: false)
        else {
            Issue.record("Cancelling scope confirmation must not repair the assignment")
            return
        }
        #expect(try workspace.templateAssignment(for: root) == assignment)
        guard
            case .repaired = workspace.repairDocumentTemplate(plan, replacement: root.appending(path: "replacement.md"))
        else {
            Issue.record("Unavailable source root must not prevent repair to an accessible source")
            return
        }
        #expect(try Data(contentsOf: source) == Data("saved".utf8))
    }

    @Test func failedRepairKeepsSavedBytesAndChoiceThenSuccessfulRepairSurvivesWriteFailure() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["old.md": "old", "new.md": "new"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let old = folder.appending(path: "old.md")
        let replacement = folder.appending(path: "new.md")
        try workspace.assignTemplate(old, to: folder)
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        let store = ProjectStore(fileURL: library.storageURL)
        let saved = try Data(contentsOf: store.fileURL)
        let before = library.projects
        try withBlockedWrites(to: store) { () throws in
            guard case .failed = workspace.repairDocumentTemplate(plan, replacement: replacement) else {
                Issue.record("A failed settings save must not appear committed")
                return
            }
            #expect(library.projects == before)
            #expect(try Data(contentsOf: store.fileURL) == saved)
            #expect(ProjectLibrary(store: store).projects == before)
        }
        try Data([0xff]).write(to: replacement)
        guard case .failed = workspace.repairDocumentTemplate(plan, replacement: replacement) else {
            Issue.record("Replacement text must be validated before persistence")
            return
        }
        #expect(try Data(contentsOf: store.fileURL) == saved)
        try Data("new".utf8).write(to: replacement)
        guard case .repaired(let repaired) = workspace.repairDocumentTemplate(plan, replacement: replacement) else {
            Issue.record("Expected a persisted repair")
            return
        }
        let repairedProjects = library.projects
        var operations = DocumentCreationOperations()
        operations.publish = { _, _, _ in throw POSIXError(.EACCES) }
        guard
            case .failed = workspace.createDocument(
                repaired, naming: .edited("Keep name"), now: .now, calendar: .current, operations: operations)
        else {
            Issue.record("Destination failure must not undo the repair")
            return
        }
        #expect(ProjectLibrary(store: store).projects == repairedProjects)
        #expect(try Data(contentsOf: old) == Data("old".utf8))
        #expect(try Data(contentsOf: replacement) == Data("new".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["new.md", "old.md"])
    }

}

extension DocumentRecoveryTests {
    @Test func retryAfterPartialOutputDiscardsOldExpansionAndUsesFreshSavedInputs() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": "old {filename} {time}"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let source = folder.appending(path: "source.md")
        try workspace.assignTemplate(source, to: folder)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let instant = Date(timeIntervalSince1970: 1_793_404_740)
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft", now: instant, calendar: calendar)
        var operations = DocumentCreationOperations()
        operations.write = { handle in
            try handle.write(contentsOf: Data("partial".utf8))
            throw POSIXError(.ENOSPC)
        }
        guard
            case .failed = workspace.createDocument(
                plan, naming: .edited("Keep me"), now: instant, calendar: calendar, operations: operations)
        else {
            Issue.record("Partial output must never be published")
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["source.md"])
        try Data("fresh {filename} {time}".utf8).write(to: source)
        try scratch.file("notes/Keep me.md", "Competitor")
        guard
            case .published(let created) = workspace.createDocument(
                plan, naming: .edited("Keep me"), now: instant.addingTimeInterval(120), calendar: calendar,
                operations: DocumentCreationOperations())
        else {
            Issue.record("Retry should reread saved inputs and reallocate the literal stem")
            return
        }
        #expect(created.url.lastPathComponent == "Keep me 2.md")
        #expect(try Data(contentsOf: created.url) == Data("fresh Keep me 2.md 00:01:00".utf8))
    }

    @Test func staleRepairAndEmptyOnceRequireReviewBeforeAnyMutation() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["old.md": "old", "new.md": "new"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let child = try scratch.folder("notes/child")
        try workspace.assignTemplate(folder.appending(path: "old.md"), to: folder)
        let plan = try workspace.prepareDocument(in: child, filenamePattern: "Draft")
        try workspace.assignTemplate(folder.appending(path: "new.md"), to: child)
        let before = library.projects
        guard
            case .reviewNeeded(let updated) = workspace.repairDocumentTemplate(
                plan, replacement: folder.appending(path: "new.md"))
        else {
            Issue.record("Do not repair a stale supplying ancestor")
            return
        }
        #expect(updated.assignment?.owner.relativePath == "child")
        #expect(library.projects == before)
        guard
            case .reviewNeeded = workspace.createDocument(
                plan, naming: .edited("Keep name"), recovery: .createEmptyOnce)
        else {
            Issue.record("Empty once must also revalidate the displayed context")
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).isEmpty)
        let otherProject = try library.createProject(named: "Other")
        try library.bindFolder(folder, to: otherProject.id)
        let other = Workspace(projectID: otherProject.id, library: library)
        other.activate()
        defer { other.deactivate() }
        let crossProject = library.projects
        guard case .failed = other.repairDocumentTemplate(plan, replacement: folder.appending(path: "new.md")) else {
            Issue.record("A pending repair cannot be applied to another project")
            return
        }
        #expect(library.projects == crossProject)
    }

    @Test(arguments: [Data([0xff]), Data([0x61, 0, 0x62]), Data()])
    func explicitRetryRereadsSourceAndRefreshesGeneratedOrLiteralInputs(_ broken: Data) async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": "initial"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let source = folder.appending(path: "source.md")
        try workspace.assignTemplate(source, to: folder)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let beforeMidnight = Date(timeIntervalSince1970: 1_793_404_740)
        let afterMidnight = beforeMidnight.addingTimeInterval(120)
        for naming in [DocumentNamingIntent.generated, .edited("Typed {date}")] {
            let plan = try workspace.prepareDocument(
                in: folder, filenamePattern: "{date} {time}", now: beforeMidnight, calendar: calendar)
            if broken.isEmpty {
                try FileManager.default.removeItem(at: source)
            } else {
                try broken.write(to: source)
            }
            guard
                case .sourceFailure = workspace.createDocument(
                    plan, naming: naming, now: beforeMidnight, calendar: calendar,
                    operations: DocumentCreationOperations())
            else {
                Issue.record("Missing or unsupported source must block without fallback")
                return
            }
            try Data("fresh {filename} {date} {time}".utf8).write(to: source)
            let stem = naming == .generated ? "2026-10-31 0001" : "Typed {date}"
            try scratch.file("notes/\(stem).md", "Competitor")
            var operations = DocumentCreationOperations()
            operations.publish = { directory, temporary, candidate in
                try Data("later source".utf8).write(to: source)
                if candidate == "\(stem) 2.md" { try scratch.file("notes/" + candidate, "Racer") }
                try DocumentCreationOperations.publish(directory, temporary, candidate)
            }
            guard
                case .published(let created) = workspace.createDocument(
                    plan, naming: naming, now: afterMidnight, calendar: calendar, operations: operations)
            else {
                Issue.record("User-visible Retry must take fresh inputs and retain them within its collision loop")
                return
            }
            #expect(created.url.lastPathComponent == "\(stem) 3.md")
            #expect(try Data(contentsOf: created.url) == Data("fresh \(stem) 3.md 2026-10-31 00:01:00".utf8))
            #expect(try Data(contentsOf: folder.appending(path: "\(stem).md")) == Data("Competitor".utf8))
            #expect(try Data(contentsOf: folder.appending(path: "\(stem) 2.md")) == Data("Racer".utf8))
        }
    }

    @Test func confirmedInheritedRepairPersistsIndependentlyOfCreationAndOtherReferences() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["old.md": "old", "new.md": "new saved"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let child = try scratch.folder("notes/posts/drafts")
        let other = try scratch.folder("notes/other")
        let optOut = try scratch.folder("notes/archive")
        let old = root.appending(path: "old.md")
        let replacement = root.appending(path: "new.md")
        try workspace.assignTemplate(old, to: root)
        try workspace.assignTemplate(old, to: other)
        try workspace.disableTemplate(in: optOut)
        let otherChoice = try workspace.templateAssignment(for: other)
        let optOutChoice = try workspace.templateAssignment(for: optOut)
        let plan = try workspace.prepareDocument(in: child, filenamePattern: "Draft")
        try FileManager.default.removeItem(at: old)
        guard case .sourceFailure = workspace.createDocument(plan, naming: .edited("Typed name")) else {
            Issue.record("Inherited broken choice must enter recovery")
            return
        }
        guard case .repaired(let repaired) = workspace.repairDocumentTemplate(plan, replacement: replacement) else {
            Issue.record("Confirmed replacement must repair the supplying ancestor")
            return
        }
        #expect(repaired.id == plan.id)
        #expect(repaired.assignment?.owner == plan.assignment?.owner)
        #expect(try workspace.templateAssignment(for: child) == nil)
        #expect(try workspace.templateAssignment(for: other) == otherChoice)
        #expect(try workspace.templateAssignment(for: optOut) == optOutChoice)
        guard case .cancelled = workspace.createDocument(repaired, naming: .edited("Typed name"), confirmed: false)
        else {
            Issue.record("Creation cancellation is independent of the committed repair")
            return
        }
        let relaunched = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        #expect(relaunched.projects == library.projects)
        let repairedAssignment = try #require(repaired.assignment)
        #expect(relaunched.project(workspace.projectID)?.templateAssignments.contains(repairedAssignment) == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).isEmpty)
        #expect(try Data(contentsOf: replacement) == Data("new saved".utf8))
        let next = try workspace.prepareDocument(in: child, filenamePattern: "Next")
        guard case .published(let created) = workspace.createDocument(next, naming: .edited("Typed name")) else {
            Issue.record("The persisted repair must supply the next creation")
            return
        }
        #expect(try Data(contentsOf: created.url) == Data("new saved".utf8))
    }

    @Test func emptyOnceSurvivesDestinationRetryButNotANewCreation() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let source = folder.appending(path: "source.md")
        try workspace.assignTemplate(source, to: folder)
        let before = library.projects
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        try FileManager.default.removeItem(at: source)
        guard case .sourceFailure = workspace.createDocument(plan, naming: .edited("Keep me")) else {
            Issue.record("A broken source must stop normal creation")
            return
        }
        var operations = DocumentCreationOperations()
        operations.write = { handle in
            try handle.write(contentsOf: Data("partial".utf8))
            throw POSIXError(.ENOSPC)
        }
        guard
            case .failed = workspace.createDocument(
                plan, naming: .edited("Keep me"), recovery: .createEmptyOnce,
                now: .now, calendar: .current, operations: operations)
        else {
            Issue.record("Empty once must use safe publication and report write failure")
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        try scratch.file("notes/Keep me.md", "Competitor")
        guard case .published(let created) = workspace.createDocument(plan, naming: .edited("Keep me")) else {
            Issue.record("Destination retry must retain the pending empty-once choice")
            return
        }
        #expect(created.url.lastPathComponent == "Keep me 2.md")
        #expect(created.editorCaretUTF16 == 0)
        #expect(try Data(contentsOf: created.url).isEmpty)
        #expect(try String(contentsOf: folder.appending(path: "Keep me.md"), encoding: .utf8) == "Competitor")
        #expect(library.projects == before)
        let next = try workspace.prepareDocument(in: folder, filenamePattern: "Next")
        guard case .sourceFailure = workspace.createDocument(next, naming: .generated) else {
            Issue.record("A separate command must use the configured source again")
            return
        }
    }
}
