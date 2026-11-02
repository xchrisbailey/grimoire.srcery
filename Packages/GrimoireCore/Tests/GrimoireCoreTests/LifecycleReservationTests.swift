import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite(.mainActorGate) struct LifecycleReservationTests {
    @Test(arguments: [false, true], [false, true])
    func pendingAssignmentBlocksItsOtherEndpointBeforeRenameOrDrag(ownerPending: Bool, rename: Bool) async throws {
        let fixture = try await ReservationFixture()
        let workspace = fixture.workspace
        defer { workspace.deactivate() }
        let first = ownerPending ? fixture.owner : fixture.source
        let moved = try fixture.leavePendingMove(first)
        let second = ownerPending ? fixture.source : fixture.owner
        let before = fixture.library.projects
        let bytes = try Data(contentsOf: fixture.library.storageURL)
        let result =
            rename ? workspace.rename(second, to: "renamed") : workspace.move(second, into: fixture.otherTarget)
        #expect(result.movedURL == nil)
        #expect(result.error != nil)
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(
            !FileManager.default.fileExists(atPath: fixture.otherTarget.appending(path: second.lastPathComponent).path))
        #expect(
            !FileManager.default.fileExists(
                atPath: second.deletingLastPathComponent().appending(path: ownerPending ? "renamed.md" : "renamed").path
            ))
        #expect(fixture.library.projects == before)
        #expect(try Data(contentsOf: fixture.library.storageURL) == bytes)
        workspace.reconcileLifecycleOperations()
        #expect(!workspace.hasPendingLifecycleOperations)
        #expect(workspace.lastError == nil)
        let owner = ownerPending ? moved : fixture.owner
        let source = ownerPending ? fixture.source : moved
        let reference = try #require(workspace.reference(for: source))
        #expect(try workspace.templateAssignment(for: owner)?.choice == .useSource(reference))
    }

    @Test func independentAssignmentsCanStillMoveWhileAnOperationIsPending() async throws {
        let fixture = try await ReservationFixture()
        let workspace = fixture.workspace
        defer { workspace.deactivate() }
        let independent = try fixture.scratch.folder("notes/independent")
        let source = try fixture.scratch.file("notes/other.md", "other bytes")
        try workspace.assignTemplate(source, to: independent)
        _ = try fixture.leavePendingMove(fixture.source)
        let result = workspace.rename(independent, to: "independent-renamed")
        #expect(result.error == nil)
        let renamed = try #require(result.movedURL)
        #expect(workspace.hasPendingLifecycleOperations)
        workspace.reconcileLifecycleOperations()
        #expect(!workspace.hasPendingLifecycleOperations)
        let reference = try #require(workspace.reference(for: source))
        #expect(try workspace.templateAssignment(for: renamed)?.choice == .useSource(reference))
        #expect(
            ProjectLibrary(store: ProjectStore(fileURL: fixture.library.storageURL)).projects
                == fixture.library.projects)
    }

    @Test func directLibraryInsertionCannotBypassConfigurationReservations() async throws {
        let fixture = try await ReservationFixture()
        let workspace = fixture.workspace
        defer { workspace.deactivate() }
        var captured: Project?
        workspace.lifecycleOperations.rename = { _, _ in
            captured = try ProjectStore(fileURL: fixture.library.storageURL).load().first
            throw CocoaError(.userCancelled)
        }
        _ = workspace.rename(fixture.owner, to: "renamed-owner")
        let candidate = try #require(captured?.pendingLifecycleOperations.first)
        #expect(!workspace.hasPendingLifecycleOperations)
        _ = try fixture.leavePendingMove(fixture.source)
        let before = fixture.library.projects
        let bytes = try Data(contentsOf: fixture.library.storageURL)
        #expect(throws: (any Error).self) {
            try fixture.library.update(workspace.projectID) { $0.pendingLifecycleOperations.append(candidate) }
        }
        #expect(fixture.library.projects == before)
        #expect(try Data(contentsOf: fixture.library.storageURL) == bytes)
        workspace.reconcileLifecycleOperations()
        #expect(!workspace.hasPendingLifecycleOperations)
    }
}

@MainActor private struct ReservationFixture {
    let scratch: Scratch
    let workspace: Workspace
    let library: ProjectLibrary
    let source: URL
    let owner: URL
    let target: URL
    let otherTarget: URL

    init() async throws {
        let scratch = try Scratch()
        self.scratch = scratch
        (workspace, library) = try await scratch.workspace(files: ["source.md": "saved bytes"])
        source = scratch.url.appending(path: "notes/source.md")
        owner = try scratch.folder("notes/owner")
        target = try scratch.folder("notes/target")
        otherTarget = try scratch.folder("notes/other-target")
        try workspace.assignTemplate(source, to: owner)
    }

    func leavePendingMove(_ source: URL) throws -> URL {
        let directory = library.storageURL.deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            workspace.lifecycleOperations.move = { try FileOperations.move($0, into: $1) }
        }
        workspace.lifecycleOperations.move = { url, destination in
            let moved = try FileOperations.move(url, into: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            return moved
        }
        let result = workspace.move(source, into: target)
        #expect(result.error != nil)
        #expect(workspace.hasPendingLifecycleOperations)
        return try #require(result.movedURL)
    }
}
