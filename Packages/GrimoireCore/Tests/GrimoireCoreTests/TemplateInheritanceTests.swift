import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite(.mainActorGate) struct TemplateInheritanceTests {
    @Test func optOutStopsInheritanceDeeperChoiceReenablesAndInheritRemovesOnlyLocalChoice() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "root source"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let archive = try scratch.folder("notes/archive")
        let ordinary = try scratch.folder("notes/archive/ordinary")
        let special = try scratch.folder("notes/archive/special")
        let source = root.appending(path: "source.md")
        try workspace.assignTemplate(source, to: root)
        try workspace.disableTemplate(in: archive)
        let disabled = try workspace.prepareDocument(in: ordinary, filenamePattern: "Empty")
        #expect(disabled.assignment?.choice == .noTemplate)
        #expect(!disabled.requiresNaming)
        guard case .published(let empty) = workspace.createDocument(disabled, naming: .generated) else {
            Issue.record("An inherited opt-out must retain legacy creation")
            return
        }
        #expect(empty.editorCaretUTF16 == nil)
        #expect(try Data(contentsOf: empty.url).isEmpty)
        try workspace.assignTemplate(source, to: special)
        let enabled = try workspace.prepareDocument(in: special, filenamePattern: "Enabled")
        guard case .published(let created) = workspace.createDocument(enabled, naming: .generated) else {
            Issue.record("A deeper source must override an opt-out")
            return
        }
        #expect(try String(contentsOf: created.url, encoding: .utf8) == "root source")
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        try withBlockedWrites(to: ProjectStore(fileURL: library.storageURL)) { () throws in
            #expect(throws: (any Error).self) { try workspace.inheritTemplate(in: archive) }
            #expect(throws: (any Error).self) { try workspace.disableTemplate(in: special) }
            #expect(library.projects == before)
            #expect(try Data(contentsOf: library.storageURL) == bytes)
        }
        try workspace.inheritTemplate(in: ordinary)
        #expect(try workspace.templateAssignment(for: archive)?.choice == .noTemplate)
        try workspace.inheritTemplate(in: archive)
        #expect(try workspace.templateAssignment(for: archive) == nil)
        #expect(try workspace.effectiveTemplateAssignment(for: ordinary)?.owner.relativePath == "")
        #expect(try workspace.templateAssignment(for: special) != nil)
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test func descendantsUseTheNearestSourceAndKeepExactChoicesSeparate() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["outer.md": "outer", "inner.md": "inner"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let posts = try scratch.folder("notes/posts")
        let destination = try scratch.folder("notes/posts/drafts")
        try workspace.assignTemplate(root.appending(path: "outer.md"), to: root)
        let inherited = try workspace.prepareDocument(in: destination, filenamePattern: "Inherited")
        #expect(inherited.assignment?.owner.relativePath == "")
        #expect(inherited.requiresNaming)
        #expect(try workspace.templateAssignment(for: destination) == nil)
        guard case .published(let first) = workspace.createDocument(inherited, naming: .edited("Inherited")) else {
            Issue.record("An actual descendant destination must inherit the root source")
            return
        }
        #expect(try String(contentsOf: first.url, encoding: .utf8) == "outer")
        try workspace.assignTemplate(root.appending(path: "inner.md"), to: posts)
        let overridden = try workspace.prepareDocument(in: destination, filenamePattern: "Override")
        #expect(overridden.assignment?.owner.relativePath == "posts")
        guard case .published(let second) = workspace.createDocument(overridden, naming: .generated) else {
            Issue.record("The nearer source must replace, not merge, inherited content")
            return
        }
        #expect(try String(contentsOf: second.url, encoding: .utf8) == "inner")
    }
}

extension TemplateInheritanceTests {
    @Test func inheritedOwnerAndOptOutChangesRequireReviewButShadowedEditsDoNot() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved", "other.md": "other"])
        let other = Workspace(projectID: workspace.projectID, library: library)
        other.activate()
        defer { workspace.deactivate(); other.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let posts = try scratch.folder("notes/posts")
        let destination = try scratch.folder("notes/posts/drafts")
        let source = root.appending(path: "source.md")
        try workspace.assignTemplate(source, to: root)
        let inherited = try workspace.prepareDocument(in: destination, filenamePattern: "Draft")
        try other.assignTemplate(source, to: posts)
        guard case .reviewNeeded(let nearer) = workspace.createDocument(inherited, naming: .edited("Keep {date}"))
        else {
            Issue.record("The same source supplied by a different owner must still require review")
            return
        }
        #expect(nearer.assignment?.owner.relativePath == "posts")
        try other.assignTemplate(root.appending(path: "other.md"), to: root)
        guard case .published(let unchanged) = workspace.createDocument(nearer, naming: .edited("Keep {date}")) else {
            Issue.record("A shadowed ancestor change must not require review")
            return
        }
        #expect(unchanged.url.lastPathComponent == "Keep {date}.md")
        #expect(try String(contentsOf: unchanged.url, encoding: .utf8) == "saved")
        let beforeOptOut = try workspace.prepareDocument(in: destination, filenamePattern: "Draft")
        try other.disableTemplate(in: posts)
        guard case .reviewNeeded(let disabled) = workspace.createDocument(beforeOptOut, naming: .edited("Keep me"))
        else {
            Issue.record("An inherited opt-out change must require review")
            return
        }
        #expect(disabled.assignment?.choice == .noTemplate)
        try other.inheritTemplate(in: posts)
        guard case .reviewNeeded(let restored) = workspace.createDocument(disabled, naming: .edited("Keep me")) else {
            Issue.record("Removing an opt-out must review the newly effective ancestor")
            return
        }
        #expect(restored.assignment?.owner.relativePath == "")
        guard case .published(let created) = workspace.createDocument(restored, naming: .edited("Keep me")) else {
            Issue.record("Reviewed inherited source must preserve literal naming intent")
            return
        }
        #expect(created.url.lastPathComponent == "Keep me.md")
        #expect(try String(contentsOf: created.url, encoding: .utf8) == "other")
    }

    @Test func unconfiguredInnerBindingStillChangesThePinnedDestinationContext() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: [:])
        defer { workspace.deactivate() }
        let posts = try scratch.folder("notes/posts")
        let destination = try scratch.folder("notes/posts/drafts")
        let plan = try workspace.prepareDocument(in: destination, filenamePattern: "Legacy")
        try library.bindFolder(posts, to: workspace.projectID)
        guard case .reviewNeeded(let updated) = workspace.createDocument(plan, naming: .edited("Keep me")) else {
            Issue.record("A different destination binding requires review even when both choices are absent")
            return
        }
        #expect(updated.assignment == nil)
        guard case .published(let created) = workspace.createDocument(updated, naming: .edited("Keep me")) else {
            Issue.record("Reviewed untemplated creation should retain its legacy handoff")
            return
        }
        #expect(created.editorCaretUTF16 == nil)
        #expect(created.url.lastPathComponent == "Keep me.md")
        #expect(try Data(contentsOf: created.url).isEmpty)
    }
}

extension TemplateInheritanceTests {
    @Test func inheritedSourceInAnUnavailableBindingStillRequiresNamingAndReportsItsOwner() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: [:])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let templates = try scratch.folder("templates")
        let source = try scratch.file("templates/source.md", "saved")
        let binding = try library.bindFolder(templates, to: workspace.projectID)
        try workspace.assignTemplate(source, to: root)
        let index = try #require(library.project(workspace.projectID)?.roots.firstIndex { $0.id == binding.id })
        try library.update(workspace.projectID) {
            $0.roots[index].bookmark = Data([0xff])
        }
        let destination = try scratch.folder("notes/child")
        let plan = try workspace.prepareDocument(in: destination, filenamePattern: "Blocked")
        #expect(plan.requiresNaming)
        #expect(plan.assignment?.owner.relativePath == "")
        guard case .sourceFailure(let failed, _) = workspace.createDocument(plan, naming: .edited("Keep me")) else {
            Issue.record("An unavailable source binding must block without borrowing stale access")
            return
        }
        #expect(failed.assignment == plan.assignment)
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }

    @Test func innerBindingMasksButRetainsOuterRecordsAndAliasOrderRequiresReview() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "outer source"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let posts = try scratch.folder("notes/posts")
        let drafts = try scratch.folder("notes/posts/drafts")
        try workspace.assignTemplate(root.appending(path: "source.md"), to: posts)
        let outerChoices = try #require(library.project(workspace.projectID)?.templateAssignments)
        let inherited = try workspace.prepareDocument(in: drafts, filenamePattern: "Before")
        let inner = try library.bindFolder(posts, to: workspace.projectID)
        guard case .reviewNeeded(let masked) = workspace.createDocument(inherited, naming: .edited("Keep me")) else {
            Issue.record("A new inner boundary must require review, not use the outer assignment")
            return
        }
        #expect(masked.assignment == nil)
        #expect(library.project(workspace.projectID)?.templateAssignments == outerChoices)
        guard case .published(let empty) = workspace.createDocument(masked, naming: .edited("Keep me")) else {
            Issue.record("Reviewed inner binding should publish empty content")
            return
        }
        #expect(empty.url.lastPathComponent == "Keep me.md")
        #expect(try Data(contentsOf: empty.url).isEmpty)
        let direct = try workspace.prepareDocument(in: drafts, filenamePattern: "Legacy")
        #expect(!direct.requiresNaming)
        try workspace.assignTemplate(root.appending(path: "source.md"), to: posts)
        let alias = FolderRoot(name: "Alias", bookmark: inner.bookmark, lastKnownPath: inner.lastKnownPath)
        try library.update(workspace.projectID) { $0.roots.append(alias) }
        let chosen = try workspace.prepareDocument(in: drafts, filenamePattern: "Chosen")
        #expect(chosen.assignment?.owner.rootID == inner.id)
        guard case .published(let templated) = workspace.createDocument(chosen, naming: .generated) else {
            Issue.record("Equivalent-depth aliases must use project order")
            return
        }
        #expect(try String(contentsOf: templated.url, encoding: .utf8) == "outer source")
        let beforeReorder = try workspace.prepareDocument(in: drafts, filenamePattern: "Reorder")
        try library.update(workspace.projectID) { $0.roots.swapAt(1, 2) }
        guard case .reviewNeeded(let reordered) = workspace.createDocument(beforeReorder, naming: .edited("Literal"))
        else {
            Issue.record("Changing the winning alias must need review")
            return
        }
        #expect(reordered.assignment == nil)
        guard case .published(let aliasEmpty) = workspace.createDocument(reordered, naming: .edited("Literal")) else {
            Issue.record("The newly winning unconfigured alias must remain empty")
            return
        }
        #expect(try Data(contentsOf: aliasEmpty.url).isEmpty)
        #expect(library.project(workspace.projectID)?.templateAssignments.first == outerChoices.first)
    }

    @Test func actualDestinationAndActiveProjectDetermineCreationNotAnUnrelatedSelection() async throws {
        let scratch = try Scratch()
        let (first, library) = try await scratch.workspace(files: ["one.md": "one", "two.md": "two"])
        let root = scratch.url.appending(path: "notes")
        let selectedFolder = try scratch.folder("notes/selected")
        let destination = try scratch.folder("notes/actual/child")
        let project = try library.createProject(named: "Second")
        try library.bindFolder(root, to: project.id)
        let second = Workspace(projectID: project.id, library: library)
        second.activate()
        defer { first.deactivate(); second.deactivate() }
        try first.assignTemplate(root.appending(path: "one.md"), to: root)
        try first.assignTemplate(root.appending(path: "two.md"), to: selectedFolder)
        let one = try first.prepareDocument(in: destination, filenamePattern: "First")
        let unconfigured = try second.prepareDocument(in: destination, filenamePattern: "Empty")
        guard case .published(let empty) = second.createDocument(unconfigured, naming: .generated) else {
            Issue.record("Another project cannot lend its assignments")
            return
        }
        #expect(empty.editorCaretUTF16 == nil)
        #expect(try Data(contentsOf: empty.url).isEmpty)
        try second.assignTemplate(root.appending(path: "two.md"), to: root)
        let two = try second.prepareDocument(in: destination, filenamePattern: "Second")
        for (workspace, plan, content) in [(first, one, "one"), (second, two, "two")] {
            guard case .published(let created) = workspace.createDocument(plan, naming: .generated) else {
                Issue.record("Each project must create with its own destination's inherited choice")
                return
            }
            #expect(created.url.deletingLastPathComponent().standardizedFileURL == destination.standardizedFileURL)
            #expect(try String(contentsOf: created.url, encoding: .utf8) == content)
        }
    }

    @Test func brokenInheritedSourceBlocksWithoutAncestorFallbackAndUnresolvedChoiceIsInactive() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["outer.md": "outer", "inner.md": "inner"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let posts = try scratch.folder("notes/posts")
        let destination = try scratch.folder("notes/posts/drafts")
        let inner = root.appending(path: "inner.md")
        try workspace.assignTemplate(root.appending(path: "outer.md"), to: root)
        try workspace.assignTemplate(inner, to: posts)
        try FileManager.default.removeItem(at: inner)
        let plan = try workspace.prepareDocument(in: destination, filenamePattern: "Blocked")
        #expect(plan.assignment?.owner.relativePath == "posts")
        guard case .sourceFailure(let failed, _) = workspace.createDocument(plan, naming: .edited("Keep me")) else {
            Issue.record("A broken inherited source must not fall back to a valid ancestor")
            return
        }
        #expect(failed.assignment?.owner.relativePath == "posts")
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
        try library.update(workspace.projectID) {
            $0.templateAssignments[1].state = .unresolved
        }
        let inactive = try workspace.prepareDocument(in: destination, filenamePattern: "Active ancestor")
        #expect(inactive.assignment?.owner.relativePath == "")
        guard case .published(let created) = workspace.createDocument(inactive, naming: .generated) else {
            Issue.record("Unresolved folder choices must stay inactive")
            return
        }
        #expect(try String(contentsOf: created.url, encoding: .utf8) == "outer")
    }
}
