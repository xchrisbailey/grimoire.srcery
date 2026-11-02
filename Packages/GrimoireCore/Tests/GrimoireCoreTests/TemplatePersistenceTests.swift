import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite(.mainActorGate) struct TemplatePersistenceTests {
    nonisolated private static let root = "6F9619FF-8B86-D011-B42D-00C04FC964FF"
    nonisolated private static let owner = "\"owner\":{\"rootID\":\"\(root)\",\"relativePath\":\"\"}"
    nonisolated private static let source = "\"source\":{\"rootID\":\"\(root)\",\"relativePath\":\"base.md\"}"

    private func json(_ field: String) -> String {
        """
        {"version":1,"projects":[{"id":"\(Self.root)","name":"Notes","icon":"book.closed",
        "color":"magic","roots":[],"expandedFolders":[]\(field)}]}
        """
    }

    @Test func legacyAbsenceIsEmptyButExplicitChoicesAndUnresolvedStateRoundTrip() async throws {
        let scratch = try Scratch()
        let legacy = try scratch.file("legacy.json", json(""))
        #expect(try ProjectStore(fileURL: legacy).load().first?.templateAssignments == [])
        let (workspace, library) = try await scratch.workspace(files: ["base.md": "source"])
        defer { workspace.deactivate() }
        let root = try #require(workspace.folders.first?.id)
        let choices = [
            FolderTemplateAssignment(owner: FileReference(rootID: root, relativePath: ""), choice: .noTemplate),
            FolderTemplateAssignment(
                owner: FileReference(rootID: root, relativePath: "missing"),
                choice: .useSource(FileReference(rootID: root, relativePath: "base.md")), state: .unresolved),
            FolderTemplateAssignment(
                owner: FileReference(rootID: root, relativePath: "archive"), choice: .noTemplate, state: .unresolved),
        ]
        try library.update(workspace.projectID) { $0.templateAssignments = choices }
        let relaunched = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        #expect(relaunched.project(workspace.projectID)?.templateAssignments == choices)
        #expect(try workspace.templateAssignment(for: scratch.url.appending(path: "notes")) == choices[0])
        let reappeared = try scratch.folder("notes/missing")
        #expect(try workspace.templateAssignment(for: reappeared)?.state == .unresolved)
    }

    @Test(arguments: [
        "null", "{}", "true", "[1]",
        "[{\(owner),\"mode\":\"unknown\",\"state\":\"active\"}]",
        "[{\(owner),\"mode\":\"useSource\",\"state\":\"active\"}]",
        "[{\(owner),\(source),\"mode\":\"noTemplate\",\"state\":\"active\"}]",
        "[{\(owner),\"mode\":\"noTemplate\",\"state\":\"unknown\"}]",
        "[{\(owner),\"mode\":\"noTemplate\"}]",
        "[{\(owner),\"mode\":17,\"state\":\"active\"}]",
        "[{\"owner\":{\"rootID\":\"not-a-uuid\",\"relativePath\":\"\"},"
            + "\"mode\":\"noTemplate\",\"state\":\"active\"}]",
        "[{\(owner),\"source\":{\"rootID\":\"\(root)\",\"relativePath\":17},"
            + "\"mode\":\"useSource\",\"state\":\"active\"}]",
        "[{\(owner),\"mode\":\"noTemplate\",\"state\":\"active\"},"
            + "{\(owner),\(source),\"mode\":\"useSource\",\"state\":\"active\"}]",
    ])
    func malformedAssignmentsBlockEditsAndPreserveStoredBytes(records: String) throws {
        let scratch = try Scratch()
        let file = try scratch.file("projects.json", json(",\"templateAssignments\":" + records))
        let original = try Data(contentsOf: file)
        let library = ProjectLibrary(store: ProjectStore(fileURL: file))
        #expect(library.loadError != nil)
        library.lastError = nil
        #expect(throws: (any Error).self) { try library.createProject(named: "Must not replace") }
        library.retryLoad()
        #expect(library.loadError != nil)
        #expect(try Data(contentsOf: file) == original)
    }

    @Test(arguments: ["/absolute", "../outside", "a/../b", "a/./b", "a//b", "a/", "\\outside"])
    func decodedAndProgrammaticReferencesRejectUnsafePaths(path: String) throws {
        let scratch = try Scratch()
        let escaped = String(decoding: try JSONEncoder().encode(path), as: UTF8.self)
        for ownerIsInvalid in [true, false] {
            let ownerPath = ownerIsInvalid ? escaped : "\"\""
            let sourcePath = ownerIsInvalid ? "\"base.md\"" : escaped
            let record = """
                {"owner":{"rootID":"\(Self.root)","relativePath":\(ownerPath)},
                "source":{"rootID":"\(Self.root)","relativePath":\(sourcePath)},
                "mode":"useSource","state":"active"}
                """
            let file = try scratch.file("projects.json", json(",\"templateAssignments\":[" + record + "]"))
            #expect(ProjectLibrary(store: ProjectStore(fileURL: file)).loadError != nil)
        }
        let store = ProjectStore(fileURL: scratch.url.appending(path: "valid.json"))
        let library = ProjectLibrary(store: store)
        let project = try library.createProject(named: "Notes")
        let bytes = try Data(contentsOf: store.fileURL)
        #expect(throws: (any Error).self) {
            try library.update(project.id) {
                $0.templateAssignments = [
                    FolderTemplateAssignment(
                        owner: FileReference(rootID: project.id, relativePath: path), choice: .noTemplate)
                ]
            }
        }
        #expect(library.projects == [project])
        #expect(try Data(contentsOf: store.fileURL) == bytes)
    }

    @Test func sourceCannotUseEmptyRootPathAndDecodedDirectorySourceIsIneligible() async throws {
        let scratch = try Scratch()
        let file = try scratch.file(
            "projects.json",
            json(
                ",\"templateAssignments\":[{\(Self.owner),\"source\":{\"rootID\":\"\(Self.root)\","
                    + "\"relativePath\":\"\"},\"mode\":\"useSource\",\"state\":\"active\"}]"))
        #expect(ProjectLibrary(store: ProjectStore(fileURL: file)).loadError != nil)
        let store = ProjectStore(fileURL: scratch.url.appending(path: "separate.json"))
        let library = ProjectLibrary(store: store)
        let project = try library.createProject(named: "Notes")
        let folder = try scratch.folder("notes")
        let root = try library.bindFolder(folder, to: project.id)
        try scratch.folder("notes/directory.md")
        try library.update(project.id) {
            $0.templateAssignments = [
                FolderTemplateAssignment(
                    owner: FileReference(rootID: root.id, relativePath: ""),
                    choice: .useSource(FileReference(rootID: root.id, relativePath: "directory.md")))
            ]
        }
        let relaunched = ProjectLibrary(store: store)
        let workspace = Workspace(projectID: project.id, library: relaunched)
        workspace.activate()
        defer { workspace.deactivate() }
        let assignment = try #require(try workspace.templateAssignment(for: folder))
        #expect(throws: TemplateAssignmentError.self) { try workspace.templateSourceURL(for: assignment) }
    }
}
