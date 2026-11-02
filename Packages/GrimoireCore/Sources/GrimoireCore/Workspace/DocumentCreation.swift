import Darwin
import Foundation

/// Internal I/O seams keep competing creators and disk failures reproducible in real folders.
struct DocumentCreationOperations {
    var write: (FileHandle) throws -> Void = { try $0.write(contentsOf: Data()) }
    var publish: (Int32, String, String) throws -> Void = { try Self.publish($0, $1, $2) }

    /// Moves `temporary` to `candidate` without ever replacing an existing entry.
    ///
    /// `RENAME_EXCL` does that atomically. Volumes that lack it (exFAT) answer `ENOTSUP`, and only then
    /// does publication fall back to claiming `candidate` with an exclusive create and renaming over the
    /// claim. A crash in between leaves an empty claim, never a partial document.
    static func publish(
        _ directory: Int32, _ temporary: String, _ candidate: String,
        renameExclusive: (Int32, String, String) throws -> Void = Self.renameExclusive,
        afterClaim: (String) throws -> Void = { _ in }
    ) throws {
        do {
            try renameExclusive(directory, temporary, candidate)
        } catch let error as POSIXError where error.code == .ENOTSUP || error.code == .EOPNOTSUPP {
            try publishOverClaim(directory, temporary, candidate, afterClaim: afterClaim)
        }
    }

    static func renameExclusive(_ directory: Int32, _ temporary: String, _ candidate: String) throws {
        guard renameatx_np(directory, temporary, directory, candidate, UInt32(RENAME_EXCL)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func publishOverClaim(
        _ directory: Int32, _ temporary: String, _ candidate: String, afterClaim: (String) throws -> Void
    ) throws {
        // O_EXCL makes an existing file, or a symlink, at the final name a collision rather than a target.
        let claim = openat(directory, candidate, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o666)
        guard claim >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(claim) }
        do {
            try afterClaim(candidate)
            // A competitor that filled or replaced the claim owns that name now. Report a collision and
            // leave their file alone so the caller moves on to the next name.
            guard isEmptyClaim(directory, candidate, claim: claim) else { throw POSIXError(.EEXIST) }
            guard renameat(directory, temporary, directory, candidate) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            // Only our own claim, and only while it is still empty, is ours to remove.
            if isEmptyClaim(directory, candidate, claim: claim) { unlinkat(directory, candidate, 0) }
            throw error
        }
    }

    /// Whether `name` is still the regular, empty file the `claim` descriptor created. The descriptor is
    /// compared live, because some volumes synthesize inodes and change them as a file's content changes.
    private static func isEmptyClaim(_ directory: Int32, _ name: String, claim: Int32) -> Bool {
        var current = stat()
        return fstatat(directory, name, &current, AT_SYMLINK_NOFOLLOW) == 0
            && current.st_mode & S_IFMT == S_IFREG && current.st_size == 0 && current.st_nlink == 1
            && FileOperations.isSameFile(claim, current)
    }
}

extension FileOperations {
    static func createDocument(
        in folder: URL, named baseName: String = "Untitled", extension ext: String = "md",
        operations: DocumentCreationOperations,
        content: (String) throws -> Data = { _ in Data() },
        validate: () throws -> Void = {}
    ) throws -> URL {
        let initialName = ext.isEmpty ? baseName : "\(baseName).\(ext)"
        // Directory-relative publication must accept only a single filename, never a path or a C-string prefix.
        guard !initialName.isEmpty, initialName != ".", initialName != "..",
            !initialName.contains("/"), !initialName.contains("\0")
        else { throw FileOperationError.invalidName(initialName) }
        let directory = open(folder.path(percentEncoded: false), O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directory >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(directory) }
        var destinationIdentity = stat()
        guard fstat(directory, &destinationIdentity) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let temporary = ".grimoire-create-\(UUID().uuidString)"
        let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o666)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        // The temporary is recognised through a descriptor that outlives the writes, not a saved inode
        // number: volumes that synthesize inodes renumber a file once it has content.
        let witness = dup(descriptor)
        guard witness >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(witness) }
        defer {
            // A replaced temporary path is not ours to remove.
            if matches(directory: directory, name: temporary, witness: witness) {
                unlinkat(directory, temporary, 0)
            }
        }
        let publication = DocumentPublication(
            folder: folder, directory: directory, destinationIdentity: destinationIdentity,
            temporary: temporary, witness: witness, handle: handle)
        return try publishDocument(
            publication, filename: (stem: baseName, extension: ext), operations: operations,
            content: content, validate: validate)
    }

    private static func publishDocument(
        _ publication: DocumentPublication, filename: (stem: String, extension: String),
        operations: DocumentCreationOperations, content: (String) throws -> Data, validate: () throws -> Void
    ) throws -> URL {
        let (baseName, ext) = filename
        var index = 1
        for attempt in 0..<32 {
            let name = try nextDocumentName(
                in: publication.directory, baseName: baseName, extension: ext, index: &index)
            let bytes = try content(name)
            // Collision output is generated for the allocated name, from the caller's one saved snapshot.
            try publication.write(bytes, retry: attempt > 0, operations: operations)
            try validate()
            try publication.validateTemporary(named: name)
            do {
                return try publication.publish(named: name, operations: operations, validate: validate)
            } catch let error as POSIXError where error.code == .EEXIST {
                index += 1
            }
        }
        throw FileOperationError.couldNotCreate(ext.isEmpty ? baseName : "\(baseName).\(ext)")
    }

    private struct DocumentPublication {
        let folder: URL
        let directory: Int32
        let destinationIdentity: stat
        let temporary: String
        let witness: Int32
        let handle: FileHandle

        func write(_ bytes: Data, retry: Bool, operations: DocumentCreationOperations) throws {
            let output: FileHandle
            if retry {
                let reopened = openat(directory, temporary, O_WRONLY | O_NOFOLLOW | O_CLOEXEC)
                guard reopened >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                output = FileHandle(fileDescriptor: reopened, closeOnDealloc: true)
            } else {
                output = handle
            }
            var current = stat()
            guard fstat(output.fileDescriptor, &current) == 0, FileOperations.isSameFile(witness, current)
            else { throw FileOperationError.couldNotCreate(temporary) }
            try validateTemporary(named: temporary)
            try output.truncate(atOffset: 0)
            try output.write(contentsOf: bytes)
            try operations.write(output)
            try output.close()
        }

        func validateTemporary(named name: String) throws {
            guard matches(directory: directory, name: temporary, witness: witness),
                matchesDestination(folder, identity: destinationIdentity)
            else { throw FileOperationError.couldNotCreate(name) }
        }

        func publish(
            named name: String, operations: DocumentCreationOperations, validate: () throws -> Void
        ) throws -> URL {
            try operations.publish(directory, temporary, name)
            let url = folder.appending(path: name)
            // Exclusive rename protects the destination name, not the source's identity.
            // Preserve a substituted entry rather than rolling back someone else's content.
            guard matches(directory: directory, name: name, witness: witness),
                matchesDestination(folder, identity: destinationIdentity)
            else { throw DocumentPublicationError.publishedButUnavailable(url) }
            do { try validate() } catch { throw DocumentPublicationError.publishedButUnavailable(url) }
            return url
        }
    }

    private static func nextDocumentName(
        in directory: Int32, baseName: String, extension ext: String, index: inout Int
    ) throws -> String {
        while true {
            let stem = index == 1 ? baseName : "\(baseName) \(index)"
            let name = ext.isEmpty ? stem : "\(stem).\(ext)"
            var existing = stat()
            if fstatat(directory, name, &existing, AT_SYMLINK_NOFOLLOW) != 0 {
                guard errno == ENOENT else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                return name
            }
            index += 1
        }
    }

    private static func matches(directory: Int32, name: String, witness: Int32) -> Bool {
        var current = stat()
        return fstatat(directory, name, &current, AT_SYMLINK_NOFOLLOW) == 0
            && current.st_mode & S_IFMT == S_IFREG && isSameFile(witness, current)
    }

    /// Whether `descriptor` refers to the file `other` describes, judged by the filesystem's current
    /// numbers for both.
    static func isSameFile(_ descriptor: Int32, _ other: stat) -> Bool {
        var current = stat()
        return fstat(descriptor, &current) == 0
            && current.st_dev == other.st_dev && current.st_ino == other.st_ino
    }

    private static func matchesDestination(_ folder: URL, identity: stat) -> Bool {
        var current = stat()
        return stat(folder.path(percentEncoded: false), &current) == 0
            && current.st_dev == identity.st_dev && current.st_ino == identity.st_ino
    }
}

enum DocumentPublicationError: Error, Equatable {
    case publishedButUnavailable(URL)
}
