import Darwin
import Foundation
import Testing

@testable import GrimoireCore

@Suite struct DocumentCreationTests {
    enum TemporaryReplacement: CaseIterable {
        case symlink, foreignFile
    }

    @Test(arguments: TemporaryReplacement.allCases)
    func substitutedTemporaryIsNotHandedOffAndItsPublishedEntryIsPreserved(_ replacement: TemporaryReplacement) throws {
        let scratch = try Scratch()
        let existing = try scratch.file("existing.md", "Existing user document")
        let foreign = try scratch.file("foreign.md", "Another creator's content")
        let published = scratch.url.appending(path: "Untitled.md")
        var operations = DocumentCreationOperations()
        operations.publish = { directory, temporary, candidate in
            let temporaryURL = scratch.url.appending(path: temporary)
            try FileManager.default.removeItem(at: temporaryURL)
            switch replacement {
            case .symlink:
                try FileManager.default.createSymbolicLink(
                    atPath: temporaryURL.path, withDestinationPath: "existing.md")
            case .foreignFile:
                try FileManager.default.moveItem(at: foreign, to: temporaryURL)
            }
            try DocumentCreationOperations.publish(directory, temporary, candidate)
        }
        var opened: URL?
        #expect(throws: DocumentPublicationError.publishedButUnavailable(published)) {
            opened = try FileOperations.createDocument(in: scratch.url, operations: operations)
        }
        #expect(opened == nil)
        #expect(try String(contentsOf: existing, encoding: .utf8) == "Existing user document")
        switch replacement {
        case .symlink:
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: published.path) == "existing.md")
            #expect(try String(contentsOf: foreign, encoding: .utf8) == "Another creator's content")
            #expect(try String(contentsOf: published, encoding: .utf8) == "Existing user document")
        case .foreignFile:
            #expect(try published.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true)
            #expect(try String(contentsOf: published, encoding: .utf8) == "Another creator's content")
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: scratch.url.path)
        #expect(!names.contains { $0.hasPrefix(".grimoire-create-") })
    }

    @Test func creationCannotPublishOutsideItsDestinationDirectory() throws {
        let scratch = try Scratch()
        let destination = try scratch.folder("notes")
        #expect(throws: FileOperationError.invalidName("../escape.md")) {
            try FileOperations.createDocument(in: destination, named: "../escape")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.url.path) == ["notes"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }

    @Test func destinationChangedDuringPublicationDoesNotHandOffAnUnrelatedFile() throws {
        let scratch = try Scratch()
        let destination = try scratch.folder("notes")
        let moved = scratch.url.appending(path: "moved")
        var operations = DocumentCreationOperations()
        operations.publish = { directory, temporary, candidate in
            try FileManager.default.moveItem(at: destination, to: moved)
            try scratch.file("notes/Untitled.md", "Not the created document")
            try DocumentCreationOperations.publish(directory, temporary, candidate)
        }
        var opened: URL?
        #expect(throws: DocumentPublicationError.publishedButUnavailable(destination.appending(path: "Untitled.md"))) {
            opened = try FileOperations.createDocument(in: destination, operations: operations)
        }
        #expect(opened == nil)
        #expect(
            try String(contentsOf: destination.appending(path: "Untitled.md"), encoding: .utf8)
                == "Not the created document")
        // Publication already succeeded in the pinned directory; do not roll it back through a changed path.
        #expect(try FileManager.default.contentsOfDirectory(atPath: moved.path) == ["Untitled.md"])
    }

    @Test func cleanupDoesNotRemoveAReplacedTemporaryFile() throws {
        let scratch = try Scratch()
        var replacement: URL?
        var operations = DocumentCreationOperations()
        operations.write = { _ in
            let names = try FileManager.default.contentsOfDirectory(atPath: scratch.url.path)
            let name = try #require(names.first)
            let temporary = scratch.url.appending(path: name)
            try FileManager.default.removeItem(at: temporary)
            replacement = try scratch.file(name, "Not ours")
            throw POSIXError(.EIO)
        }
        #expect(throws: POSIXError(.EIO)) {
            try FileOperations.createDocument(in: scratch.url, operations: operations)
        }
        let preserved = try #require(replacement)
        #expect(try String(contentsOf: preserved, encoding: .utf8) == "Not ours")
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.url.path) == [preserved.lastPathComponent])
    }

    @Test func danglingSymlinkIsAnOccupiedName() throws {
        let scratch = try Scratch()
        let link = scratch.url.appending(path: "Untitled.md")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "missing.md")
        let created = try FileOperations.createDocument(in: scratch.url)
        #expect(created.lastPathComponent == "Untitled 2.md")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == "missing.md")
    }

    @Test func missingDestinationDoesNotCreateOrRedirect() throws {
        let scratch = try Scratch()
        #expect(throws: POSIXError(.ENOENT)) {
            try FileOperations.createDocument(in: scratch.url.appending(path: "missing"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.url.path).isEmpty)
    }

    @Test func existingNamesDoNotConsumePublicationAttempts() throws {
        let scratch = try Scratch()
        try scratch.file("Notes.txt", "Existing")
        for index in 2...40 { try scratch.file("Notes \(index).txt", "Existing") }
        let created = try FileOperations.createDocument(in: scratch.url, named: "Notes", extension: "txt")
        #expect(created.lastPathComponent == "Notes 41.txt")
        #expect(try Data(contentsOf: created).isEmpty)
        #expect(try String(contentsOf: scratch.url.appending(path: "Notes 40.txt"), encoding: .utf8) == "Existing")
    }

    @Test func partialWriteFailureLeavesNoFinalDocumentOrTemporaryArtifact() throws {
        let scratch = try Scratch()
        let unrelated = try scratch.file(".grimoire-create-unrelated", "Keep me")
        var operations = DocumentCreationOperations()
        operations.write = { handle in
            try handle.write(contentsOf: Data("Partial".utf8))
            #expect(!FileManager.default.fileExists(atPath: scratch.url.appending(path: "Untitled.md").path))
            throw POSIXError(.ENOSPC)
        }
        var opened: URL?
        #expect(throws: POSIXError(.ENOSPC)) {
            opened = try FileOperations.createDocument(in: scratch.url, operations: operations)
        }
        #expect(opened == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.url.path) == [unrelated.lastPathComponent])
        #expect(try String(contentsOf: unrelated, encoding: .utf8) == "Keep me")
    }

    @Test(arguments: [POSIXErrorCode.ENOTSUP, .EACCES, .EIO])
    func publicationFailureFailsClosedWithoutSuccessfulHandoff(_ code: POSIXErrorCode) throws {
        let scratch = try Scratch()
        var operations = DocumentCreationOperations()
        operations.publish = { _, _, _ in throw POSIXError(code) }
        var opened: URL?
        #expect(throws: POSIXError(code)) {
            opened = try FileOperations.createDocument(in: scratch.url, operations: operations)
        }
        #expect(opened == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.url.path).isEmpty)
    }

    @Test func completeClosedTemporaryIsPublishedOnlyAfterWritingFinishes() throws {
        let scratch = try Scratch()
        var operations = DocumentCreationOperations()
        var descriptor: Int32 = -1
        operations.write = { handle in
            descriptor = handle.fileDescriptor
            try handle.write(contentsOf: Data("First\r\n".utf8))
            #expect(!FileManager.default.fileExists(atPath: scratch.url.appending(path: "Untitled.md").path))
            try handle.write(contentsOf: Data("Last".utf8))
        }
        operations.publish = { directory, temporary, candidate in
            // Another test in the process can reuse the closed descriptor's number, so ask what
            // it refers to instead of whether it exists.
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if fcntl(descriptor, F_GETPATH, &path) == 0 {
                let held = URL(filePath: String(cString: path)).resolvingSymlinksInPath()
                #expect(held != scratch.url.appending(path: temporary).resolvingSymlinksInPath())
            } else {
                #expect(errno == EBADF)
            }
            #expect(try Data(contentsOf: scratch.url.appending(path: temporary)) == Data("First\r\nLast".utf8))
            try DocumentCreationOperations.publish(directory, temporary, candidate)
        }
        let created = try FileOperations.createDocument(in: scratch.url, operations: operations)
        #expect(try Data(contentsOf: created) == Data("First\r\nLast".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.url.path) == ["Untitled.md"])
    }

    @Test func changedDestinationFailsWithoutRedirectingCreation() throws {
        let scratch = try Scratch()
        let destination = try scratch.folder("notes")
        let moved = scratch.url.appending(path: "moved")
        var operations = DocumentCreationOperations()
        operations.write = { _ in
            try FileManager.default.moveItem(at: destination, to: moved)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        }
        var opened: URL?
        #expect(throws: FileOperationError.couldNotCreate("Untitled.md")) {
            opened = try FileOperations.createDocument(in: destination, operations: operations)
        }
        #expect(opened == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: moved.path).isEmpty)
    }

    @Test func publicationExhaustionReturnsNoDocumentAndPreservesEveryCompetitor() throws {
        let scratch = try Scratch()
        var operations = DocumentCreationOperations()
        var attempts = 0
        operations.publish = { directory, temporary, candidate in
            attempts += 1
            // The 33rd call would succeed, making an unbounded implementation fail rather than hang.
            if attempts <= 32 { try scratch.file(candidate, "Competitor \(attempts)") }
            try DocumentCreationOperations.publish(directory, temporary, candidate)
        }
        var opened: URL?
        #expect(throws: FileOperationError.couldNotCreate("Untitled.md")) {
            opened = try FileOperations.createDocument(in: scratch.url, operations: operations)
        }
        #expect(opened == nil)
        #expect(attempts == 32)
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.url.path).count == 32)
        #expect(
            try String(contentsOf: scratch.url.appending(path: "Untitled 32.md"), encoding: .utf8) == "Competitor 32")
    }

    @Test func competingCreatorKeepsItsBytesAndCreationUsesTheNextName() throws {
        let scratch = try Scratch()
        var operations = DocumentCreationOperations()
        operations.publish = { directory, temporary, candidate in
            if candidate == "Untitled.md" {
                try scratch.file(candidate, "Another writer")
            }
            try DocumentCreationOperations.publish(directory, temporary, candidate)
        }
        let created = try FileOperations.createDocument(in: scratch.url, operations: operations)
        #expect(created.lastPathComponent == "Untitled 2.md")
        #expect(try String(contentsOf: scratch.url.appending(path: "Untitled.md"), encoding: .utf8) == "Another writer")
        #expect(try Data(contentsOf: created).isEmpty)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: scratch.url.path).sorted()
                == ["Untitled 2.md", "Untitled.md"])
    }
}
