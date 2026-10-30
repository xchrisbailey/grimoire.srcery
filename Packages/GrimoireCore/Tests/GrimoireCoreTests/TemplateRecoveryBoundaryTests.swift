import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct TemplateRecoveryBoundaryTests {
    @Test func locateUsesMostSpecificBindingAndRetainsMaskedOuterAndOtherProjectChoices() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "source"])
        defer { workspace.deactivate() }
        let owner = try scratch.folder("notes/posts")
        let target = try scratch.folder("notes/target")
        let root = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(root.appending(path: "source.md"), to: owner)
        try workspace.disableTemplate(in: target)
        let outerChoice = try #require(try workspace.templateAssignment(for: target))
        let otherProject = try library.createProject(named: "Other")
        try library.bindFolder(root, to: otherProject.id)
        let other = Workspace(projectID: otherProject.id, library: library)
        other.activate()
        defer { other.deactivate() }
        try other.disableTemplate(in: target)
        let otherBefore = other.project
        try FileManager.default.removeItem(at: owner)
        workspace.refreshTemplateAssignments()
        let inactive = try #require(workspace.unresolvedTemplateAssignments.first)
        let inner = try library.bindFolder(target, to: workspace.projectID)
        workspace.sync()
        #expect(try workspace.effectiveTemplateAssignment(for: target) == nil)
        let plan = try workspace.prepareTemplateRecovery(inactive, locating: target)
        #expect(plan.destinationOwner == FileReference(rootID: inner.id, relativePath: ""))
        try workspace.confirmTemplateRecovery(plan)
        #expect(workspace.project?.templateAssignments.contains(outerChoice) == true)
        #expect(workspace.project?.templateAssignments.count == 2)
        #expect(try workspace.effectiveTemplateAssignment(for: target)?.choice == inactive.choice)
        #expect(other.project == otherBefore)
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test func explicitAuthoringCanReplaceAnInactiveChoiceButOrdinaryCreationCannotReactivateIt() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": "old"])
        defer { workspace.deactivate() }
        let owner = try scratch.folder("notes/posts")
        try workspace.assignTemplate(scratch.url.appending(path: "notes/source.md"), to: owner)
        try FileManager.default.removeItem(at: owner)
        workspace.refreshTemplateAssignments()
        try scratch.folder("notes/posts")
        let plan = try workspace.prepareDocument(in: owner, filenamePattern: "New")
        guard case .published(let ordinary) = workspace.createDocument(plan, naming: .generated) else {
            Issue.record("Inactive owners must permit ordinary untemplated creation")
            return
        }
        #expect(try Data(contentsOf: ordinary.url).isEmpty)
        #expect(workspace.unresolvedTemplateAssignments.count == 1)
        let authoring = try workspace.prepareTemplateSource(in: owner, assigningTo: owner)
        guard case .assigned(let created) = workspace.createTemplateSource(authoring, named: "Template") else {
            Issue.record("Explicit template authoring must still work for an inactive owner")
            return
        }
        #expect(try Data(contentsOf: created.url).isEmpty)
        #expect(workspace.unresolvedTemplateAssignments.isEmpty)
        #expect(try workspace.templateAssignment(for: owner)?.state == .active)
    }
}
