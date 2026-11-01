import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite(.mainActorGate) struct LifecycleKindCompatibilityTests {
    @Test(arguments: [
        "root identity", "projections", "empty projections", "null root", "null projections", "bad root",
        "bad projections", "null kind", "unknown kind", "missing kind",
    ])
    func trashRejectsRelocationFieldsAndInvalidKindsWithoutOverwriting(field: String) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "original"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let source = root.appending(path: "source.md")
        try workspace.assignTemplate(source, to: root)
        let plan = try workspace.prepareTrash(source)
        var intent = Data()
        var operation: PendingLifecycleOperation?
        workspace.lifecycleOperations.trash = { _ in
            intent = try Data(contentsOf: library.storageURL)
            operation = try ProjectStore(fileURL: library.storageURL).load().first?.pendingLifecycleOperations.first
            throw CocoaError(.userCancelled)
        }
        #expect(throws: (any Error).self) { try workspace.confirmDestructiveOperation(plan) }
        let recorded = try #require(operation)
        let bytes = try malformedTrash(field, intent: intent, operation: recorded)
        try bytes.write(to: library.storageURL, options: .atomic)
        let rejected = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        #expect(rejected.loadError != nil)
        #expect(throws: (any Error).self) { try rejected.createProject(named: "Must not overwrite") }
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        #expect(try String(contentsOf: source, encoding: .utf8) == "original")
    }

    @Test(arguments: ["same root", "cross root", "projected"])
    func missingKindPreservesLegacyRelocationAndRoundTripsItsEvidence(mode: String) async throws {
        let fixture = try await LifecycleSourceCoordinateFixture()
        defer { fixture.workspace.deactivate() }
        if mode != "projected" { try fixture.workspace.inheritTemplate(in: fixture.outerOwner) }
        var intent = Data()
        if mode == "same root" {
            fixture.workspace.lifecycleOperations.rename = { _, _ in
                intent = try Data(contentsOf: fixture.library.storageURL)
                throw CocoaError(.userCancelled)
            }
            _ = fixture.workspace.rename(fixture.source, to: "renamed")
        } else {
            (intent, _) = try fixture.captureMove(completed: false)
        }
        let original = try #require(String(data: intent, encoding: .utf8))
        let legacy = original.replacingOccurrences(
            of: #"(?m)^\s*"kind" : "relocation",\n"#, with: "", options: .regularExpression)
        try #require(legacy != original)
        let store = ProjectStore(fileURL: fixture.library.storageURL)
        try Data(legacy.utf8).write(to: store.fileURL, options: .atomic)
        let loaded = ProjectLibrary(store: store)
        #expect(loaded.loadError == nil)
        let before = loaded.projects
        try store.save(before)
        #expect(ProjectLibrary(store: store).projects == before)
        let restarted = Workspace(projectID: fixture.workspace.projectID, library: loaded)
        restarted.activate()
        defer { restarted.deactivate() }
        #expect(!restarted.hasPendingLifecycleOperations && restarted.lastError == nil)
        #expect(try String(contentsOf: fixture.source, encoding: .utf8) == "original {title}")
    }

    @Test(arguments: ["[]", "null", "{}"])
    func relocationRejectsTrashScopesWithoutOverwriting(value: String) async throws {
        let fixture = try await LifecycleSourceCoordinateFixture()
        defer { fixture.workspace.deactivate() }
        let (intent, _) = try fixture.captureMove(completed: false)
        let original = try #require(String(data: intent, encoding: .utf8))
        let malformed = original.replacingOccurrences(
            of: "\"kind\" : \"relocation\"", with: "\"trashRoots\" : " + value + ", \"kind\" : \"relocation\"")
        try #require(malformed != original)
        let bytes = Data(malformed.utf8)
        try bytes.write(to: fixture.library.storageURL, options: .atomic)
        let rejected = ProjectLibrary(store: ProjectStore(fileURL: fixture.library.storageURL))
        #expect(rejected.loadError != nil)
        #expect(throws: (any Error).self) { try rejected.createProject(named: "Must not overwrite") }
        #expect(try Data(contentsOf: fixture.library.storageURL) == bytes)
    }

    private func malformedTrash(
        _ field: String, intent: Data, operation: PendingLifecycleOperation
    ) throws -> Data {
        let original = try #require(String(data: intent, encoding: .utf8))
        let encoder = JSONEncoder()
        let identity = try #require(String(data: encoder.encode(operation.rootIdentity), encoding: .utf8))
        let projections = try #require(
            String(
                data: encoder.encode([
                    LifecycleSourceProjection(source: operation.source, rootIdentity: operation.rootIdentity)
                ]), encoding: .utf8))
        let replacement: String
        switch field {
        case "root identity": replacement = "\"destinationRootIdentity\" : " + identity + ", \"kind\" : \"trash\""
        case "projections": replacement = "\"sourceProjections\" : " + projections + ", \"kind\" : \"trash\""
        case "empty projections": replacement = "\"sourceProjections\" : [], \"kind\" : \"trash\""
        case "null root": replacement = "\"destinationRootIdentity\" : null, \"kind\" : \"trash\""
        case "null projections": replacement = "\"sourceProjections\" : null, \"kind\" : \"trash\""
        case "bad root": replacement = "\"destinationRootIdentity\" : {}, \"kind\" : \"trash\""
        case "bad projections": replacement = "\"sourceProjections\" : [{}], \"kind\" : \"trash\""
        case "null kind": replacement = "\"kind\" : null"
        case "unknown kind": replacement = "\"kind\" : \"future\""
        default: replacement = "\"unknownKind\" : \"trash\""
        }
        let malformed = original.replacingOccurrences(of: "\"kind\" : \"trash\"", with: replacement)
        try #require(malformed != original)
        return Data(malformed.utf8)
    }
}
