import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct TemplateInheritanceTests {
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
