import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite(.mainActorGate) struct TemplateAuthoringTests {
    @Test func publicationIdentitySurvivesReplayAndAuthoringCaretAdaptation() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace()
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let plan = try workspace.prepareTemplateSource(in: folder, assigningTo: folder)
        guard case .assigned(let source) = workspace.createTemplateSource(plan, named: "Template"),
            case .assigned(let replay) = workspace.createTemplateSource(plan, named: "Template")
        else {
            Issue.record("One publication must survive authoring/replayed results"); return
        }
        #expect(source.id == replay.id)
        #expect(source.editorCaretUTF16 == 0 && replay.editorCaretUTF16 == 0)
        #expect(try source.matchesPublishedItem(at: source.url))
        try Data("replacement".utf8).write(to: source.url, options: .atomic)
        #expect(try !source.matchesPublishedItem(at: source.url))
        #expect(try !replay.matchesPublishedItem(at: replay.url))
        try FileManager.default.removeItem(at: source.url)
        let nextPlan = try workspace.prepareTemplateSource(in: folder, assigningTo: folder)
        guard case .assigned(let next) = workspace.createTemplateSource(nextPlan, named: "Template") else {
            Issue.record("A new publication may legitimately reuse the URL"); return
        }
        #expect(next.url == source.url && next.id != source.id)
        #expect(try next.matchesPublishedItem(at: next.url))
        #expect(try !source.matchesPublishedItem(at: next.url))
    }

    @Test func inheritedSourceIsAnOrdinaryDocumentAndAuthoringOverridesOnlyTheEditedFolder() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "ancestor", "existing.md": "keep"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let source = root.appending(path: "source.md")
        let editedFolder = try scratch.folder("notes/posts")
        let destination = try scratch.folder("notes/posts/templates")
        try workspace.assignTemplate(source, to: root)
        let ancestor = try #require(try workspace.templateAssignment(for: root))
        let inherited = try #require(try workspace.effectiveTemplateAssignment(for: editedFolder))
        #expect(inherited == ancestor)
        #expect(try workspace.templateAssignment(for: editedFolder) == nil)
        let before = library.projects
        let openedSource = try #require(try workspace.templateSourceURL(for: inherited))
        let document = try OpenDocument(url: openedSource, autosaveDelay: .seconds(3600))
        defer { document.discard() }
        document.text = "saved ordinary source\r\n"
        document.save()
        #expect(library.projects == before)
        #expect(try workspace.effectiveTemplateAssignment(for: editedFolder) == ancestor)
        #expect(try workspace.prepareDocument(in: destination, filenamePattern: "Draft").assignment == ancestor)

        let plan = try workspace.prepareTemplateSource(in: destination, assigningTo: editedFolder)
        guard case .assigned(let created) = workspace.createTemplateSource(plan, named: "Empty") else {
            Issue.record("Authoring must bypass the destination's inherited source")
            return
        }
        #expect(try Data(contentsOf: created.url).isEmpty)
        #expect(created.editorCaretUTF16 == 0)
        #expect(try workspace.templateAssignment(for: root) == ancestor)
        let local = try #require(try workspace.templateAssignment(for: editedFolder))
        #expect(local.owner.relativePath == "posts")
        #expect(try workspace.templateSourceURL(for: local) == created.url.resolvingSymlinksInPath())
        #expect(try workspace.effectiveTemplateAssignment(for: destination) == local)
        #expect(try String(contentsOf: source, encoding: .utf8) == "saved ordinary source\r\n")
        #expect(try String(contentsOf: root.appending(path: "existing.md"), encoding: .utf8) == "keep")
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test func emptySourceBypassesItsOwnAssignmentAndCommitsOnlyAfterPublication() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "inherited content"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(folder.appending(path: "source.md"), to: folder)
        let before = library.projects
        let plan = try workspace.prepareTemplateSource(in: folder, assigningTo: folder)
        #expect(library.projects == before)
        guard case .assigned(let source) = workspace.createTemplateSource(plan, named: "New source") else {
            Issue.record("Authoring must publish and persist the new source")
            return
        }
        #expect(try Data(contentsOf: source.url).isEmpty)
        #expect(source.editorCaretUTF16 == 0)
        let assignment = try #require(try workspace.templateAssignment(for: folder))
        #expect(try workspace.templateSourceURL(for: assignment) == source.url.resolvingSymlinksInPath())
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
        #expect(try String(contentsOf: folder.appending(path: "source.md"), encoding: .utf8) == "inherited content")
    }

    @Test func failedCommitPreservesPublishedSourceAndOldChoiceWithoutDuplicateRetry() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "old choice"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(folder.appending(path: "source.md"), to: folder)
        let before = library.projects
        let store = ProjectStore(fileURL: library.storageURL)
        let storedBytes = try Data(contentsOf: store.fileURL)
        let plan = try workspace.prepareTemplateSource(in: folder, assigningTo: folder)
        try withBlockedWrites(to: store) { () throws in
            guard case .unassigned(let source, let error) = workspace.createTemplateSource(plan, named: "New") else {
                Issue.record("A source published before a failed settings commit is a distinct partial success")
                return
            }
            #expect(!error.localizedDescription.isEmpty)
            #expect(try Data(contentsOf: source.url).isEmpty)
            #expect(library.projects == before)
            #expect(try Data(contentsOf: store.fileURL) == storedBytes)
            #expect(ProjectLibrary(store: store).projects == before)
        }
        guard case .unassigned(let source, _) = workspace.createTemplateSource(plan, named: "New") else {
            Issue.record("Retry must preserve the partial outcome, not create or silently assign another source")
            return
        }
        #expect(source.url.lastPathComponent == "New.md")
        #expect(library.projects == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["New.md", "source.md"])
        try workspace.assignTemplate(source.url, to: folder)
        #expect(ProjectLibrary(store: store).projects == library.projects)
    }

    @Test func cancellationInvalidNamesAndFailedPublicationLeaveNoSourceOrSettingsChanges() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "old"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(folder.appending(path: "source.md"), to: folder)
        let before = library.projects
        let stored = try Data(contentsOf: library.storageURL)
        let plan = try workspace.prepareTemplateSource(in: folder, assigningTo: folder)
        guard case .cancelled = workspace.createTemplateSource(plan, named: "../escape", confirmed: false) else {
            Issue.record("Cancellation must bypass all side effects")
            return
        }
        for invalid in ["", "..", "../escape", "a/b", "a\\b", " spaced ", ".hidden", "a\n"] {
            guard case .failed = workspace.createTemplateSource(plan, named: invalid) else {
                Issue.record("Invalid literal authoring name must fail: \(invalid)")
                return
            }
        }
        var operations = DocumentCreationOperations()
        operations.publish = { _, _, _ in throw POSIXError(.ENOSPC) }
        guard case .failed = workspace.createTemplateSource(plan, named: "New", operations: operations) else {
            Issue.record("Source publication failure must not assign")
            return
        }
        #expect(library.projects == before)
        #expect(try Data(contentsOf: library.storageURL) == stored)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["source.md"])
    }

    @Test func eligibleOtherBindingAllowsAuthoringButUnboundAndEscapingLocationsDoNot() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: [:])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let outside = try scratch.folder("outside")
        let link = folder.appending(path: "escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        for location in [outside, link, folder.appending(path: "missing"), folder.appending(path: "../outside")] {
            #expect(throws: (any Error).self) {
                try workspace.prepareTemplateSource(in: location, assigningTo: folder)
            }
        }
        let templates = try scratch.folder("templates")
        try library.bindFolder(templates, to: workspace.projectID)
        let plan = try workspace.prepareTemplateSource(in: templates, assigningTo: folder)
        guard case .assigned(let source) = workspace.createTemplateSource(plan, named: "Shared") else {
            Issue.record("Sources may live in any currently bound folder")
            return
        }
        #expect(source.url.deletingLastPathComponent().resolvingSymlinksInPath() == templates.resolvingSymlinksInPath())
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test func collisionsNeverReplaceAndRepeatedConfirmationDoesNotCreateAnotherSource() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["Template.md": "competitor"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let plan = try workspace.prepareTemplateSource(in: folder, assigningTo: folder)
        guard case .assigned(let source) = workspace.createTemplateSource(plan, named: "Template") else {
            Issue.record("Expected a collision-safe source")
            return
        }
        #expect(source.url.lastPathComponent == "Template 2.md")
        guard case .assigned(let repeated) = workspace.createTemplateSource(plan, named: "Template") else {
            Issue.record("Expected the same terminal authoring outcome")
            return
        }
        #expect(repeated.url == source.url)
        #expect(try String(contentsOf: folder.appending(path: "Template.md"), encoding: .utf8) == "competitor")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
    }

    @Test func sharedOrdinarySourceUsesOnlySavedEditsForFutureDocuments() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["existing.md": "never rewrite me"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let first = try scratch.folder("notes/first")
        let second = try scratch.folder("notes/second")
        let plan = try workspace.prepareTemplateSource(in: folder, assigningTo: first)
        guard case .assigned(let source) = workspace.createTemplateSource(plan, named: "Shared") else {
            Issue.record("Expected ordinary empty source")
            return
        }
        try workspace.assignTemplate(source.url, to: second)
        let document = try OpenDocument(url: source.url, autosaveDelay: .seconds(3600))
        defer { document.discard() }
        document.text = "first saved\r\n"
        document.save()
        let firstPlan = try workspace.prepareDocument(in: first, filenamePattern: "First")
        document.text = "unsaved buffer"
        guard case .published(let original) = workspace.createDocument(firstPlan, naming: .generated) else {
            Issue.record("Expected saved source, not buffer")
            return
        }
        #expect(try String(contentsOf: original.url, encoding: .utf8) == "first saved\r\n")
        document.text = "second saved\n"
        document.save()
        let secondPlan = try workspace.prepareDocument(in: second, filenamePattern: "Second")
        document.text = "another unsaved buffer"
        guard case .published(let updated) = workspace.createDocument(secondPlan, naming: .generated) else {
            Issue.record("Saved source edits must be live for all assignments")
            return
        }
        #expect(try String(contentsOf: updated.url, encoding: .utf8) == "second saved\n")
        #expect(try String(contentsOf: original.url, encoding: .utf8) == "first saved\r\n")
        #expect(try String(contentsOf: folder.appending(path: "existing.md"), encoding: .utf8) == "never rewrite me")
        #expect(try String(contentsOf: source.url, encoding: .utf8) == "second saved\n")
    }
}
