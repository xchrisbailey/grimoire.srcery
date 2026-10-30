import Darwin
import Foundation

/// Internal I/O seams keep competing creators and disk failures reproducible in real folders.
struct DocumentCreationOperations {
    var write: (FileHandle) throws -> Void = { try $0.write(contentsOf: Data()) }
    var publish: (Int32, String, String) throws -> Void = Self.publish

    static func publish(_ directory: Int32, _ temporary: String, _ candidate: String) throws {
        // RENAME_EXCL fails closed on filesystems without exclusive rename support.
        guard renameatx_np(directory, temporary, directory, candidate, UInt32(RENAME_EXCL)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

extension FileOperations {
    static func createDocument(
        in folder: URL, named baseName: String = "Untitled", extension ext: String = "md",
        operations: DocumentCreationOperations
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
        var identity = stat()
        guard fstat(descriptor, &identity) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            // A replaced temporary path is not ours to remove.
            if matches(directory: directory, name: temporary, identity: identity) {
                unlinkat(directory, temporary, 0)
            }
        }
        try operations.write(handle)
        try handle.close()
        var index = 1
        for _ in 0..<32 {
            let name = try nextDocumentName(in: directory, baseName: baseName, extension: ext, index: &index)
            guard matches(directory: directory, name: temporary, identity: identity),
                matchesDestination(folder, identity: destinationIdentity)
            else {
                throw FileOperationError.couldNotCreate(name)
            }
            do {
                try operations.publish(directory, temporary, name)
                // Exclusive rename protects the destination name, not the source's identity.
                // Preserve a substituted entry rather than rolling back someone else's content.
                guard matches(directory: directory, name: name, identity: identity),
                    matchesDestination(folder, identity: destinationIdentity)
                else {
                    throw FileOperationError.couldNotCreate(name)
                }
                return folder.appending(path: name)
            } catch let error as POSIXError where error.code == .EEXIST {
                index += 1
            }
        }
        throw FileOperationError.couldNotCreate(initialName)
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

    private static func matches(directory: Int32, name: String, identity: stat) -> Bool {
        var current = stat()
        return fstatat(directory, name, &current, AT_SYMLINK_NOFOLLOW) == 0
            && current.st_mode & S_IFMT == S_IFREG
            && current.st_dev == identity.st_dev && current.st_ino == identity.st_ino
    }

    private static func matchesDestination(_ folder: URL, identity: stat) -> Bool {
        var current = stat()
        return stat(folder.path(percentEncoded: false), &current) == 0
            && current.st_dev == identity.st_dev && current.st_ino == identity.st_ino
    }
}
