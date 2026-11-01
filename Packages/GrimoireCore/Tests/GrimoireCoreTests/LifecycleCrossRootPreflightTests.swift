import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct LifecycleCrossRootPreflightTests {
    @Test func unavailableInnerDestinationNeverMigratesChoicesIntoTheAccessibleOuterRoot() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["posts/keep.md": "original"])
        defer { workspace.deactivate() }
        let posts = scratch.url.appending(path: "notes/posts")
        let outer = try scratch.folder("destination")
        let target = try scratch.folder("destination/inner")
        try library.bindFolder(outer, to: workspace.projectID)
        let inner = try library.bindFolder(target, to: workspace.projectID)
        try workspace.disableTemplate(in: posts)
        let index = try #require(workspace.project?.roots.firstIndex { $0.id == inner.id })
        try library.update(workspace.projectID) { $0.roots[index].bookmark = Data([0]) }
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        let result = workspace.move(posts, into: target)
        #expect(result.movedURL == nil && result.legacyMovedURL == nil && result.error != nil)
        #expect(library.projects == before)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        #expect(try String(contentsOf: posts.appending(path: "keep.md"), encoding: .utf8) == "original")
        #expect(!FileManager.default.fileExists(atPath: target.appending(path: "posts").path))
    }

    @Test(arguments: [false, true])
    func unavailableOuterRootNamesItselfWhenAnInnerItemMoves(rename: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["inner/keep.md": "original"])
        defer { workspace.deactivate() }
        let inner = scratch.url.appending(path: "notes/inner")
        let elsewhere = try scratch.folder("notes/other")
        let outer = try #require(workspace.project?.roots.first)
        try library.bindFolder(inner, to: workspace.projectID)
        try library.update(workspace.projectID) { $0.roots[0].bookmark = Data([0]) }
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        let file = inner.appending(path: "keep.md")
        let result = rename ? workspace.rename(file, to: "renamed") : workspace.move(file, into: elsewhere)
        let expected = LifecycleError.containingFolderUnavailable(outer.displayName)
        #expect(result.error as? LifecycleError == expected)
        #expect(result.error?.localizedDescription.contains(outer.displayName) == true)
        #expect(result.movedURL == nil && result.legacyMovedURL == nil)
        #expect(!workspace.hasPendingLifecycleOperations)
        #expect(library.projects == before)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        #expect(try String(contentsOf: file, encoding: .utf8) == "original")
    }

    @Test func movingAnUnavailableBoundRootsOwnFolderIsUnsupportedBecauseRegrantingCannotHelp() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["inner/keep.md": "original"])
        defer { workspace.deactivate() }
        let inner = scratch.url.appending(path: "notes/inner")
        let elsewhere = try scratch.folder("notes/other")
        let root = try library.bindFolder(inner, to: workspace.projectID)
        let index = try #require(workspace.project?.roots.firstIndex { $0.id == root.id })
        try library.update(workspace.projectID) { $0.roots[index].bookmark = Data([0]) }
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        let result = workspace.move(inner, into: elsewhere)
        #expect(result.error as? LifecycleError == .unsupportedBoundary)
        #expect(result.movedURL == nil && result.legacyMovedURL == nil)
        #expect(library.projects == before)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        #expect(try String(contentsOf: inner.appending(path: "keep.md"), encoding: .utf8) == "original")
    }

    @Test(arguments: ["", "sub"])
    func unavailableDestinationFolderIsNamedWithoutClaimingItContainsTheItem(subfolder: String) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["file.md": "original", "inner/sub/keep.md": "x"])
        defer { workspace.deactivate() }
        let inner = scratch.url.appending(path: "notes/inner")
        let root = try library.bindFolder(inner, to: workspace.projectID)
        let index = try #require(workspace.project?.roots.firstIndex { $0.id == root.id })
        try library.update(workspace.projectID) { $0.roots[index].bookmark = Data([0]) }
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        let file = scratch.url.appending(path: "notes/file.md")
        let destination = subfolder.isEmpty ? inner : inner.appending(path: subfolder)
        let result = workspace.move(file, into: destination)
        let error = try #require(result.error as? LifecycleError)
        #expect(error == .containingFolderUnavailable(root.displayName))
        let message = error.localizedDescription
        #expect(message.contains(root.displayName) && message.contains("so this move can't be checked"))
        #expect(!message.contains("contains this item"))
        #expect(library.projects == before)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        #expect(try String(contentsOf: file, encoding: .utf8) == "original")
    }

    @Test(arguments: ["filesystem", "record", "unavailable", "intent save", "filesystem failure", "cross volume"])
    func rejectedMovePreservesFilesAndBothConfigurations(reason: String) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["posts/keep.md": "original"])
        defer { workspace.deactivate() }
        let posts = scratch.url.appending(path: "notes/posts")
        let target = try scratch.folder("destination")
        let root = try library.bindFolder(target, to: workspace.projectID)
        try workspace.disableTemplate(in: posts)
        if reason == "filesystem" {
            try scratch.file("destination/posts/keep.md", "competitor")
        } else if reason == "record" {
            let child = try scratch.folder("destination/posts/child")
            try workspace.disableTemplate(in: child)
            try FileManager.default.removeItem(at: target.appending(path: "posts"))
        } else if reason == "unavailable" {
            let index = try #require(workspace.project?.roots.firstIndex { $0.id == root.id })
            try library.update(workspace.projectID) { project in
                project.roots[index].bookmark = Data([0])
            }
        } else if reason == "filesystem failure" {
            workspace.lifecycleOperations.move = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        } else if reason == "cross volume" {
            workspace.lifecycleOperations.isSameVolume = { _, _ in false }
        }
        let before = library.projects
        let store = ProjectStore(fileURL: library.storageURL)
        let bytes = try Data(contentsOf: store.fileURL)
        if reason == "intent save" {
            try withBlockedWrites(to: store) {
                let result = workspace.move(posts, into: target)
                #expect(result.movedURL == nil && result.legacyMovedURL == nil && result.error != nil)
            }
        } else {
            let result = workspace.move(posts, into: target)
            #expect(result.movedURL == nil && result.legacyMovedURL == nil && result.error != nil)
            if reason == "record" { #expect(result.error as? LifecycleError == .conflict) }
            if reason == "cross volume" { #expect(result.error as? LifecycleError == .crossVolumeConfiguration) }
        }
        #expect(library.projects == before)
        #expect(try Data(contentsOf: store.fileURL) == bytes)
        #expect(try String(contentsOf: posts.appending(path: "keep.md"), encoding: .utf8) == "original")
        if reason == "filesystem" {
            #expect(try String(contentsOf: target.appending(path: "posts/keep.md"), encoding: .utf8) == "competitor")
        } else {
            #expect(!FileManager.default.fileExists(atPath: target.appending(path: "posts").path))
        }
    }

    @Test(arguments: ["missing", "null", "wrong type", "invalid identity"])
    func malformedRootPairNeverLoadsAsLegacyOrOverwritesTheStore(scenario: String) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["posts/keep.md": "original"])
        let posts = scratch.url.appending(path: "notes/posts")
        let target = try scratch.folder("destination")
        try library.bindFolder(target, to: workspace.projectID)
        try workspace.disableTemplate(in: posts)
        var intent = Data()
        workspace.lifecycleOperations.move = { _, _ in
            intent = try Data(contentsOf: library.storageURL)
            throw CocoaError(.userCancelled)
        }
        _ = workspace.move(posts, into: target)
        workspace.deactivate()
        let original = try #require(String(data: intent, encoding: .utf8))
        let changed: String
        if scenario == "missing" {
            changed = original.replacingOccurrences(of: "\"destinationRootIdentity\"", with: "\"unknownIdentity\"")
        } else {
            let value =
                scenario == "null" ? "null" : scenario == "wrong type" ? "0" : "{\"device\":1,\"inode\":1,\"type\":0}"
            changed = original.replacingOccurrences(
                of: "\"destinationRootIdentity\"\\s*:\\s*\\{[^}]*\\}",
                with: "\"destinationRootIdentity\" : " + value, options: .regularExpression)
        }
        #expect(changed != original)
        let bytes = Data(changed.utf8)
        try bytes.write(to: library.storageURL, options: .atomic)
        let restarted = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        #expect(restarted.loadError != nil)
        #expect(throws: (any Error).self) { try restarted.createProject(named: "Must not overwrite") }
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        #expect(try String(contentsOf: posts.appending(path: "keep.md"), encoding: .utf8) == "original")
    }
}
