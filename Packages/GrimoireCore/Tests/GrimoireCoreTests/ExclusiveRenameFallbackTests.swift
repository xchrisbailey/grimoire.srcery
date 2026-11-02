import Darwin
import Foundation
import Testing

@testable import GrimoireCore

/// Volumes without `RENAME_EXCL` (exFAT) answer `ENOTSUP`; publication must then claim the name instead.
@Suite struct ExclusiveRenameFallbackTests {
    private static func unsupported(_: Int32, _: String, _: String) throws {
        throw POSIXError(.ENOTSUP)
    }

    private func operations(afterClaim: @escaping (String) throws -> Void = { _ in }) -> DocumentCreationOperations {
        var operations = DocumentCreationOperations()
        operations.publish = { directory, temporary, candidate in
            try DocumentCreationOperations.publish(
                directory, temporary, candidate, renameExclusive: Self.unsupported, afterClaim: afterClaim)
        }
        return operations
    }

    private func names(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    @Test(arguments: [POSIXErrorCode.ENOTSUP, .EOPNOTSUPP])
    func publishesWithoutRenameExclusiveAndLeavesNoTemporary(_ code: POSIXErrorCode) throws {
        let scratch = try Scratch()
        var operations = DocumentCreationOperations()
        operations.publish = { directory, temporary, candidate in
            try DocumentCreationOperations.publish(
                directory, temporary, candidate, renameExclusive: { _, _, _ in throw POSIXError(code) })
        }
        let url = try FileOperations.createDocument(
            in: scratch.url, operations: operations, content: { Data("# \($0)".utf8) })
        #expect(url.lastPathComponent == "Untitled.md")
        #expect(try Data(contentsOf: url) == Data("# Untitled.md".utf8))
        #expect(try names(scratch.url) == ["Untitled.md"])
    }

    @Test func otherRenameFailuresAreNotMistakenForMissingSupport() throws {
        let scratch = try Scratch()
        var operations = DocumentCreationOperations()
        operations.publish = { directory, temporary, candidate in
            try DocumentCreationOperations.publish(
                directory, temporary, candidate, renameExclusive: { _, _, _ in throw POSIXError(.EACCES) })
        }
        #expect(throws: POSIXError.self) { try FileOperations.createDocument(in: scratch.url, operations: operations) }
        #expect(try names(scratch.url).isEmpty)
    }

    @Test func existingFileAtTheFinalNameIsKeptAndTheNextNameIsUsed() throws {
        let scratch = try Scratch()
        try scratch.file("Draft.md", "Mine")
        var attempted: [String] = []
        var operations = DocumentCreationOperations()
        operations.publish = { directory, temporary, candidate in
            attempted.append(candidate)
            // The name looked free when allocated; a file appears before the claim is made.
            if attempted.count == 1 { try scratch.file(candidate, "Competitor") }
            try DocumentCreationOperations.publish(
                directory, temporary, candidate, renameExclusive: Self.unsupported)
        }
        let url = try FileOperations.createDocument(
            in: scratch.url, named: "Draft", operations: operations, content: { Data($0.utf8) })
        #expect(attempted == ["Draft 2.md", "Draft 3.md"])
        #expect(url.lastPathComponent == "Draft 3.md")
        #expect(try String(contentsOf: url, encoding: .utf8) == "Draft 3.md")
        #expect(try String(contentsOf: scratch.url.appending(path: "Draft.md"), encoding: .utf8) == "Mine")
        #expect(try String(contentsOf: scratch.url.appending(path: "Draft 2.md"), encoding: .utf8) == "Competitor")
        #expect(try names(scratch.url) == ["Draft 2.md", "Draft 3.md", "Draft.md"])
    }

    @Test func competitorFillingTheClaimIsNeverOverwritten() throws {
        let scratch = try Scratch()
        var claimed: [String] = []
        let operations = operations { name in
            claimed.append(name)
            if claimed.count == 1 {
                let handle = try FileHandle(forWritingTo: scratch.url.appending(path: name))
                defer { try? handle.close() }
                try handle.write(contentsOf: Data("Competitor".utf8))
            }
        }
        let url = try FileOperations.createDocument(
            in: scratch.url, named: "Draft", operations: operations, content: { Data($0.utf8) })
        #expect(claimed == ["Draft.md", "Draft 2.md"])
        #expect(url.lastPathComponent == "Draft 2.md")
        #expect(try String(contentsOf: url, encoding: .utf8) == "Draft 2.md")
        #expect(try String(contentsOf: scratch.url.appending(path: "Draft.md"), encoding: .utf8) == "Competitor")
        #expect(try names(scratch.url) == ["Draft 2.md", "Draft.md"])
    }

    @Test func competitorReplacingTheEmptyClaimIsNeverOverwritten() throws {
        let scratch = try Scratch()
        var claimed = 0
        let operations = operations { name in
            claimed += 1
            guard claimed == 1 else { return }
            let path = scratch.url.appending(path: name)
            try FileManager.default.removeItem(at: path)
            try Data().write(to: path)
        }
        let url = try FileOperations.createDocument(
            in: scratch.url, named: "Draft", operations: operations, content: { Data($0.utf8) })
        #expect(url.lastPathComponent == "Draft 2.md")
        // Their empty file stays; ours is not removed from under them or written over them.
        #expect(try Data(contentsOf: scratch.url.appending(path: "Draft.md")).isEmpty)
        #expect(try names(scratch.url) == ["Draft 2.md", "Draft.md"])
    }

    @Test func hardFailureAfterClaimingRemovesOnlyOurEmptyClaimAndTheTemporary() throws {
        let scratch = try Scratch()
        let operations = operations { _ in throw POSIXError(.EIO) }
        #expect(throws: POSIXError.self) {
            try FileOperations.createDocument(in: scratch.url, named: "Draft", operations: operations)
        }
        #expect(try names(scratch.url).isEmpty)
    }

    @Test func hardFailureKeepsAClaimACompetitorHasFilled() throws {
        let scratch = try Scratch()
        let operations = operations { name in
            try Data("Competitor".utf8).write(to: scratch.url.appending(path: name))
            throw POSIXError(.EIO)
        }
        #expect(throws: POSIXError.self) {
            try FileOperations.createDocument(in: scratch.url, named: "Draft", operations: operations)
        }
        #expect(try names(scratch.url) == ["Draft.md"])
        #expect(try String(contentsOf: scratch.url.appending(path: "Draft.md"), encoding: .utf8) == "Competitor")
    }

    @Test func writeFailureNeverClaimsTheName() throws {
        let scratch = try Scratch()
        var claimed = false
        var operations = self.operations { _ in claimed = true }
        operations.write = { _ in throw POSIXError(.ENOSPC) }
        #expect(throws: POSIXError.self) {
            try FileOperations.createDocument(in: scratch.url, operations: operations)
        }
        #expect(!claimed)
        #expect(try names(scratch.url).isEmpty)
    }
}

@MainActor @Suite(.mainActorGate) struct ExclusiveRenameFallbackWorkspaceTests {
    private var unsupported: DocumentCreationOperations {
        var operations = DocumentCreationOperations()
        operations.publish = { directory, temporary, candidate in
            try DocumentCreationOperations.publish(
                directory, temporary, candidate, renameExclusive: { _, _, _ in throw POSIXError(.ENOTSUP) })
        }
        return operations
    }

    @Test func templateDocumentCreationAndSourceAuthoringPublishWithoutRenameExclusive() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": "Hello {filename}"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let source = folder.appending(path: "source.md")
        try workspace.assignTemplate(source, to: folder)
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        guard
            case .published(let created) = workspace.createDocument(
                plan, naming: .generated, now: .now, calendar: .current, operations: unsupported)
        else {
            Issue.record("Template document creation must publish through the claim fallback")
            return
        }
        #expect(created.url.lastPathComponent == "Draft.md")
        #expect(try String(contentsOf: created.url, encoding: .utf8) == "Hello Draft.md")

        let authoring = try workspace.prepareTemplateSource(in: folder, assigningTo: folder)
        guard
            case .assigned(let newSource) = workspace.createTemplateSource(
                authoring, named: "New", operations: unsupported)
        else {
            Issue.record("Template source authoring must publish through the claim fallback")
            return
        }
        #expect(newSource.url.lastPathComponent == "New.md")
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == [
                "Draft.md", "New.md", "source.md",
            ])
    }
}
