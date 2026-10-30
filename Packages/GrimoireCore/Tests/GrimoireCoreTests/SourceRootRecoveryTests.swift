import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct SourceRootRecoveryTests {
    @Test(arguments: [true, false])
    func lostLiveSourceRootAllowsExplicitEmptyOnceWithoutChangingSettings(_ prepareBeforeLoss: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["replacement.md": "replacement"])
        defer { workspace.deactivate() }
        let notes = scratch.url.appending(path: "notes")
        let templates = try scratch.folder("templates")
        let source = try scratch.file("templates/source.md", "saved")
        try library.bindFolder(templates, to: workspace.projectID)
        workspace.sync()
        try workspace.assignTemplate(source, to: notes)
        let original = try workspace.prepareDocument(in: notes, filenamePattern: "Draft")
        let settings = try Data(contentsOf: library.storageURL)
        let assignments = library.projects
        try FileManager.default.moveItem(at: templates, to: scratch.url.appending(path: "offline"))
        let plan = try prepareBeforeLoss ? original : workspace.prepareDocument(in: notes, filenamePattern: "Draft")
        let blocked = try sourceFailure(workspace, plan)
        #expect(blocked.assignment == original.assignment)
        #expect(try FileManager.default.contentsOfDirectory(atPath: notes.path) == ["replacement.md"])
        guard
            case .published(let created) = workspace.createDocument(
                blocked, naming: .edited("Keep me"), recovery: .createEmptyOnce)
        else {
            Issue.record("Unavailable source root must not block an explicit empty-once creation")
            return
        }
        #expect(created.url.lastPathComponent == "Keep me.md")
        #expect(try Data(contentsOf: created.url).isEmpty)
        #expect(library.projects == assignments)
        #expect(try Data(contentsOf: library.storageURL) == settings)
        #expect(try Data(contentsOf: scratch.url.appending(path: "offline/source.md")) == Data("saved".utf8))
        let next = try workspace.prepareDocument(in: notes, filenamePattern: "Next")
        _ = try sourceFailure(workspace, next)
    }

    @Test(arguments: [true, false])
    func lostLiveSourceRootAllowsIndependentPersistedRepair(_ prepareBeforeLoss: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["replacement.md": "replacement {title}"])
        defer { workspace.deactivate() }
        let notes = scratch.url.appending(path: "notes")
        let child = try scratch.folder("notes/posts")
        let templates = try scratch.folder("templates")
        let source = try scratch.file("templates/source.md", "saved")
        try library.bindFolder(templates, to: workspace.projectID)
        workspace.sync()
        try workspace.assignTemplate(source, to: notes)
        let original = try workspace.prepareDocument(in: child, filenamePattern: "Draft")
        let settings = try Data(contentsOf: library.storageURL)
        try FileManager.default.moveItem(at: templates, to: scratch.url.appending(path: "offline"))
        let plan = try prepareBeforeLoss ? original : workspace.prepareDocument(in: child, filenamePattern: "Draft")
        let blocked = try sourceFailure(workspace, plan)
        let replacement = notes.appending(path: "replacement.md")
        try assertFailedRepairPreservesSettings(workspace, library: library, plan: blocked, source: replacement)
        #expect(try Data(contentsOf: library.storageURL) == settings)
        guard case .repaired(let repaired) = workspace.repairDocumentTemplate(blocked, replacement: replacement) else {
            Issue.record("Loss of the old source root must not block a confirmed eligible repair")
            return
        }
        #expect(repaired.id == plan.id)
        #expect(repaired.assignment?.owner == original.assignment?.owner)
        #expect(try workspace.templateAssignment(for: child) == nil)
        let persisted = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        #expect(persisted.projects == library.projects)
        #expect(try Data(contentsOf: library.storageURL) != settings)
        guard case .published(let created) = workspace.createDocument(repaired, naming: .edited("Keep me")) else {
            Issue.record("The repaired pending creation should use the replacement and retain the literal name")
            return
        }
        #expect(created.url.lastPathComponent == "Keep me.md")
        #expect(try Data(contentsOf: created.url) == Data("replacement Keep me".utf8))
        #expect(try Data(contentsOf: replacement) == Data("replacement {title}".utf8))
        #expect(try Data(contentsOf: scratch.url.appending(path: "offline/source.md")) == Data("saved".utf8))
    }

    @Test func restoredSourceRootRequiresReviewBeforeCreationOrRepair() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["replacement.md": "replacement"])
        defer { workspace.deactivate() }
        let notes = scratch.url.appending(path: "notes")
        let templates = try scratch.folder("templates")
        let source = try scratch.file("templates/source.md", "saved")
        try library.bindFolder(templates, to: workspace.projectID)
        workspace.sync()
        try workspace.assignTemplate(source, to: notes)
        let offline = scratch.url.appending(path: "offline")
        try FileManager.default.moveItem(at: templates, to: offline)
        let plan = try workspace.prepareDocument(in: notes, filenamePattern: "Draft")
        _ = try sourceFailure(workspace, plan)
        let settings = try Data(contentsOf: library.storageURL)
        try FileManager.default.moveItem(at: offline, to: templates)
        guard
            case .reviewNeeded = workspace.repairDocumentTemplate(
                plan, replacement: notes.appending(path: "replacement.md"))
        else {
            Issue.record("Restored source availability changes the displayed repair context")
            return
        }
        #expect(try Data(contentsOf: library.storageURL) == settings)
        guard case .reviewNeeded(let updated) = workspace.createDocument(plan, naming: .edited("Keep me")) else {
            Issue.record("Restored source availability must be reviewed before creating")
            return
        }
        guard case .published(let created) = workspace.createDocument(updated, naming: .edited("Keep me")) else {
            Issue.record("Reviewed restoration may use the same configured saved source")
            return
        }
        #expect(created.url.lastPathComponent == "Keep me.md")
        #expect(try Data(contentsOf: created.url) == Data("saved".utf8))
    }

    @Test func lostDestinationRootRemainsFatalEvenWhenEmptyOnceIsExplicit() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: [
            "source.md": "saved", "replacement.md": "replacement",
        ])
        defer { workspace.deactivate() }
        let notes = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(notes.appending(path: "source.md"), to: notes)
        let plan = try workspace.prepareDocument(in: notes, filenamePattern: "Draft")
        let settings = try Data(contentsOf: library.storageURL)
        let offline = scratch.url.appending(path: "offline")
        try FileManager.default.moveItem(at: notes, to: offline)
        guard
            case .contextUnavailable = workspace.createDocument(
                plan, naming: .edited("Keep me"), recovery: .createEmptyOnce)
        else {
            Issue.record("Empty once cannot grant destination access or recreate a missing binding")
            return
        }
        guard
            case .failed = workspace.repairDocumentTemplate(
                plan, replacement: offline.appending(path: "replacement.md"))
        else {
            Issue.record("A missing destination cannot authorize a stale assignment repair")
            return
        }
        #expect(throws: TemplateAssignmentError.self) {
            try workspace.prepareDocument(in: notes, filenamePattern: "Next")
        }
        #expect(!FileManager.default.fileExists(atPath: notes.path))
        #expect(try Data(contentsOf: library.storageURL) == settings)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: offline.path).sorted() == [
                "replacement.md", "source.md",
            ])
    }

    private func assertFailedRepairPreservesSettings(
        _ workspace: Workspace, library: ProjectLibrary, plan: DocumentCreationPlan, source: URL
    ) throws {
        let store = ProjectStore(fileURL: library.storageURL)
        let settings = try Data(contentsOf: store.fileURL)
        let projects = library.projects
        try withBlockedWrites(to: store) { () throws in
            guard case .failed = workspace.repairDocumentTemplate(plan, replacement: source) else {
                Issue.record("A confirmed repair must still fail honestly when settings persistence fails")
                return
            }
            #expect(library.projects == projects)
            #expect(try Data(contentsOf: store.fileURL) == settings)
        }
    }

    private func sourceFailure(_ workspace: Workspace, _ plan: DocumentCreationPlan) throws -> DocumentCreationPlan {
        var result = workspace.createDocument(plan, naming: .edited("Keep me"))
        if case .reviewNeeded(let updated) = result {
            #expect(updated.id == plan.id)
            result = workspace.createDocument(updated, naming: .edited("Keep me"))
        }
        guard case .sourceFailure(let blocked, _) = result else {
            Issue.record(
                "Source-root loss must reach explicit recovery after any required review, not a context dead end")
            throw TemplateAssignmentError.unavailableFolder
        }
        return blocked
    }
}
