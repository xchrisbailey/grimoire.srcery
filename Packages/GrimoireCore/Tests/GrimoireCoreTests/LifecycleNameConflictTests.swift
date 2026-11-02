import Foundation
import Testing

@testable import GrimoireCore

private enum NameCapability: CaseIterable, Sendable {
    case sensitive, insensitive, unknown
    var value: Bool? {
        switch self {
        case .sensitive: true
        case .insensitive: false
        case .unknown: nil
        }
    }
}

private enum ConflictName: CaseIterable, Sendable {
    case ascii, unicode
    var destination: String { self == .ascii ? "drafts" : "café" }
    var recorded: String { self == .ascii ? "DRAFTS" : "CAFE\u{301}" }
}

private struct NameScenario: Sendable {
    let capability: NameCapability
    let name: ConflictName
    static let cases = NameCapability.allCases.flatMap { capability in
        ConflictName.allCases.map { NameScenario(capability: capability, name: $0) }
    }
}

@MainActor @Suite(.mainActorGate) struct LifecycleNameConflictTests {
    @Test(arguments: [false, true], NameScenario.cases)
    private func missingDestinationRecordsRespectVolumeNames(rename: Bool, scenario: NameScenario) async throws {
        let capability = scenario.capability
        let name = scenario.name
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "source bytes"])
        defer { workspace.deactivate() }
        workspace.lifecycleOperations.caseSensitiveNames = { _ in capability.value }
        let parent = rename ? scratch.url.appending(path: "notes") : try scratch.folder("notes/target")
        let source = try scratch.folder(rename ? "notes/posts" : "notes/origin/" + name.destination)
        let child = try scratch.folder((rename ? "notes/posts" : "notes/origin/" + name.destination) + "/child")
        let ghost = parent.appending(path: name.recorded)
        try FileManager.default.createDirectory(at: ghost.appending(path: "child"), withIntermediateDirectories: true)
        try workspace.disableTemplate(in: source)
        try workspace.assignTemplate(scratch.url.appending(path: "notes/source.md"), to: child)
        try workspace.disableTemplate(in: ghost.appending(path: "child"))
        try FileManager.default.removeItem(at: ghost)
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        let result = rename ? workspace.rename(source, to: name.destination) : workspace.move(source, into: parent)
        if capability == .sensitive {
            #expect(result.error == nil)
            #expect(result.movedURL != nil)
            #expect(workspace.project?.templateAssignments.count == 3)
            let root = try #require(workspace.project?.roots.first?.id)
            let prefix = rename ? "" : "target/"
            #expect(
                workspace.project?.templateAssignments.contains(where: {
                    $0.owner == FileReference(rootID: root, relativePath: prefix + name.recorded + "/child")
                }) == true)
        } else {
            #expect(result.error != nil)
            #expect(result.movedURL == nil)
            #expect(FileManager.default.fileExists(atPath: source.path))
            #expect(!FileManager.default.fileExists(atPath: parent.appending(path: name.destination).path))
            #expect(library.projects == before)
            #expect(try Data(contentsOf: library.storageURL) == bytes)
        }
        #expect(!workspace.hasPendingLifecycleOperations)
    }

    @Test func sameRelativeSpellingInAnotherRootIsNotADestinationConflict() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace()
        defer { workspace.deactivate() }
        workspace.lifecycleOperations.caseSensitiveNames = { _ in false }
        let source = try scratch.folder("notes/posts")
        let other = try scratch.folder("other")
        let ghost = try scratch.folder("other/DRAFTS/child")
        try library.bindFolder(other, to: workspace.projectID)
        try workspace.disableTemplate(in: source)
        try workspace.disableTemplate(in: ghost)
        try FileManager.default.removeItem(at: ghost.deletingLastPathComponent())
        let result = workspace.rename(source, to: "drafts")
        #expect(result.error == nil)
        #expect(result.movedURL != nil)
        #expect(workspace.project?.templateAssignments.count == 2)
    }
}
