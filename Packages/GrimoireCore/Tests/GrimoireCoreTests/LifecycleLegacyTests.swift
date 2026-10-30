import Foundation
import Testing

@testable import GrimoireCore

private enum LegacyProtection: CaseIterable, Sendable {
    case none, sourceAncestor, descendant, sourceReference, destinationAncestor, destinationDescendant
    case pendingAssignment, destinationPending, inactiveAlias, destinationAlias
}

@MainActor @Suite struct LifecycleLegacyTests {
    @Test(arguments: LegacyProtection.allCases)
    private func onlyGenuinelyUnconfiguredCrossVolumeMovesUseLegacy(protection: LegacyProtection) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: [
            "posts/document.md": "legacy bytes", "template.md": "template",
        ])
        defer { workspace.deactivate() }
        let source = scratch.url.appending(path: "notes/posts")
        let destination = try scratch.folder("other")
        try library.bindFolder(destination, to: workspace.projectID)
        try configure(
            protection, destination: destination, workspace: workspace, library: library,
            scratch: scratch)
        workspace.lifecycleOperations.isSameVolume = { _, _ in false }
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        let result = workspace.move(source, into: destination)
        #expect(result.movedURL == nil)
        if protection == .none {
            #expect(result.error == nil)
            let legacy = try #require(result.legacyMovedURL)
            #expect(try String(contentsOf: legacy.appending(path: "document.md"), encoding: .utf8) == "legacy bytes")
        } else {
            #expect(result.error != nil)
            #expect(result.legacyMovedURL == nil)
            #expect(FileManager.default.fileExists(atPath: source.path))
            #expect(!FileManager.default.fileExists(atPath: destination.appending(path: "posts").path))
        }
        #expect(library.projects == before)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        #expect(
            workspace.hasPendingLifecycleOperations
                == (protection == .pendingAssignment || protection == .destinationPending))
    }

    @Test(arguments: [false, true])
    func unconfiguredSameRootCannotFallBackToLegacyWhenIdentityCannotSurvive(rename: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "original"])
        defer { workspace.deactivate() }
        let source = scratch.url.appending(path: "notes/source.md")
        let destination = try scratch.folder("notes/target")
        workspace.lifecycleOperations.isSameVolume = { _, _ in false }
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        let result = rename ? workspace.rename(source, to: "renamed") : workspace.move(source, into: destination)
        #expect(result.movedURL == nil)
        #expect(result.legacyMovedURL == nil)
        #expect(result.error != nil)
        #expect(try String(contentsOf: source, encoding: .utf8) == "original")
        #expect(!workspace.hasPendingLifecycleOperations)
        #expect(library.projects == before)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
    }

    private func configure(
        _ protection: LegacyProtection, destination: URL, workspace: Workspace,
        library: ProjectLibrary, scratch: Scratch
    ) throws {
        let source = scratch.url.appending(path: "notes/posts")
        switch protection {
        case .none: break
        case .sourceAncestor:
            try workspace.disableTemplate(in: source.deletingLastPathComponent())
        case .descendant:
            try workspace.disableTemplate(in: scratch.folder("notes/posts/child"))
        case .sourceReference:
            try workspace.assignTemplate(source.appending(path: "document.md"), to: scratch.folder("notes/owner"))
        case .destinationAncestor:
            try workspace.disableTemplate(in: destination)
        case .destinationDescendant:
            let ghost = try scratch.folder("other/posts/child")
            try workspace.disableTemplate(in: ghost)
            try FileManager.default.removeItem(at: ghost.deletingLastPathComponent())
        case .pendingAssignment:
            try leavePendingSourceMove(workspace, library: library, source: source, scratch: scratch)
        case .destinationPending:
            try leavePendingSourceMove(
                workspace, library: library, source: source, scratch: scratch, destinationContext: true)
        case .inactiveAlias, .destinationAlias:
            let alias = scratch.url.appending(path: "notes/alias")
            try FileManager.default.createSymbolicLink(
                at: alias,
                withDestinationURL: protection == .inactiveAlias ? source : destination)
            let root = try #require(workspace.project?.roots.first?.id)
            try library.update(workspace.projectID) {
                $0.templateAssignments.append(
                    FolderTemplateAssignment(
                        owner: FileReference(rootID: root, relativePath: "alias"), choice: .noTemplate,
                        state: .unresolved))
            }
        }
    }

    private func leavePendingSourceMove(
        _ workspace: Workspace, library: ProjectLibrary, source: URL,
        scratch: Scratch, destinationContext: Bool = false
    ) throws {
        let template =
            destinationContext
            ? try scratch.file("other/template.md", "template")
            : scratch.url.appending(path: "notes/template.md")
        let owner = destinationContext ? try scratch.folder("notes/owner") : source
        try workspace.assignTemplate(template, to: owner)
        let holding = try scratch.folder(destinationContext ? "other/holding" : "notes/holding")
        let directory = library.storageURL.deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            workspace.lifecycleOperations.move = { try FileOperations.move($0, into: $1) }
        }
        workspace.lifecycleOperations.move = { url, folder in
            let moved = try FileOperations.move(url, into: folder)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            return moved
        }
        let result = workspace.move(template, into: holding)
        #expect(result.movedURL != nil)
        #expect(workspace.hasPendingLifecycleOperations)
    }
}
