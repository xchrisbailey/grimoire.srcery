import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct TemplateRecoveryAccessTests {
    @Test(arguments: [false, true], [0o000, 0o400, 0o100])
    func locateRequiresLiveReadAndTraversalBeforeConsumingRecovery(prepareBeforeLoss: Bool, permissions: Int)
        async throws
    {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved source"])
        defer { workspace.deactivate() }
        let owner = try scratch.folder("notes/posts")
        let source = scratch.url.appending(path: "notes/source.md")
        try workspace.assignTemplate(source, to: owner)
        try FileManager.default.removeItem(at: owner)
        workspace.refreshTemplateAssignments()
        let inactive = try #require(workspace.unresolvedTemplateAssignments.first)
        let target = try scratch.folder("notes/located")
        let identity = try LifecycleIdentity(target)
        let plan = try prepareBeforeLoss ? workspace.prepareTemplateRecovery(inactive, locating: target) : nil
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        let rootURL = workspace.folders.first?.url
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: target.path) }
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        #expect(try LifecycleIdentity(target) == identity)
        #expect(throws: (any Error).self) {
            if let plan {
                try workspace.confirmTemplateRecovery(plan)
            } else {
                _ = try workspace.prepareTemplateRecovery(inactive, locating: target)
            }
        }
        #expect(library.projects == before)
        #expect(workspace.unresolvedTemplateAssignments == [inactive])
        #expect(workspace.folders.first?.url == rootURL)
        #expect(workspace.isActive)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == before)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: target.path)
        let restored = try plan ?? workspace.prepareTemplateRecovery(inactive, locating: target)
        try workspace.confirmTemplateRecovery(restored)
        let recovered = try #require(try workspace.templateAssignment(for: target))
        #expect(recovered.state == .active)
        #expect(recovered.choice == inactive.choice)
        #expect(workspace.unresolvedTemplateAssignments.isEmpty)
        #expect(try String(contentsOf: source, encoding: .utf8) == "saved source")
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }
}
