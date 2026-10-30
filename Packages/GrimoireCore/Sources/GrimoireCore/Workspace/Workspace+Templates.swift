import Darwin
import Foundation

extension Workspace {
    func saveTemplateAssignment(_ assignment: FolderTemplateAssignment) throws {
        if let owner = url(for: assignment.owner) { try requireNoPendingLifecycle(at: owner) }
        if case .useSource(let reference) = assignment.choice, let source = url(for: reference) {
            try requireNoPendingLifecycle(at: source)
        }
        try library.update(projectID) { project in
            project.templateAssignments.removeAll { $0.owner == assignment.owner }
            project.templateAssignments.append(assignment)
        }
    }

    func removeTemplateAssignment(ownedBy owner: FileReference) throws {
        if let url = url(for: owner) { try requireNoPendingLifecycle(at: url) }
        try library.update(projectID) { project in
            project.templateAssignments.removeAll { $0.owner == owner }
        }
    }

    /// Inspects only this folder's saved choice, including an inactive unresolved record.
    public func templateAssignment(for folder: URL) throws -> FolderTemplateAssignment? {
        sync()
        try validateActiveTemplateOwners()
        let owner = try templateOwner(for: folder)
        return project?.templateAssignments.first { $0.owner == owner }
    }

    /// The nearest active choice inside the destination's most-specific bound root.
    public func effectiveTemplateAssignment(for folder: URL) throws -> FolderTemplateAssignment? {
        sync()
        try validateActiveTemplateOwners()
        guard var owner = try templateReference(for: folder) else {
            throw TemplateAssignmentError.unavailableFolder
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            throw TemplateAssignmentError.unavailableFolder
        }
        while true {
            if let assignment = project?.templateAssignments.first(where: { $0.owner == owner && $0.state == .active })
            {
                return assignment
            }
            guard !owner.relativePath.isEmpty else { return nil }
            owner = FileReference(
                rootID: owner.rootID,
                relativePath: owner.relativePath.split(separator: "/").dropLast().joined(separator: "/"))
        }
    }

    /// Nil represents a cancelled picker, not removal of the previous choice.
    public func assignTemplate(_ source: URL?, to folder: URL) throws {
        guard let source else { return }
        sync()
        try validateActiveTemplateOwners()
        let owner = try templateOwner(for: folder)
        let reference = try templateSourceReference(for: source)
        try saveTemplateAssignment(FolderTemplateAssignment(owner: owner, choice: .useSource(reference)))
    }

    /// Resolves a stored source using live bound-root access, never last-known paths.
    public func templateSourceURL(for assignment: FolderTemplateAssignment) throws -> URL? {
        try assignment.validate()
        guard case .useSource(let reference) = assignment.choice else { return nil }
        guard let root = templateRoots.first(where: { $0.id == reference.rootID })?.url else {
            throw TemplateAssignmentError.ineligibleSource
        }
        let url = reference.url(in: root)
        _ = try templateSourceReference(for: url)
        return url.resolvingSymlinksInPath()
    }

    public func disableTemplate(in folder: URL) throws {
        sync()
        try validateActiveTemplateOwners()
        let owner = try templateOwner(for: folder)
        try saveTemplateAssignment(FolderTemplateAssignment(owner: owner, choice: .noTemplate))
    }

    /// Removes only the edited folder's choice, never the ancestor supplying its effective choice.
    public func inheritTemplate(in folder: URL) throws {
        sync()
        try validateActiveTemplateOwners()
        try removeTemplateAssignment(ownedBy: templateOwner(for: folder))
    }

    var templateRoots: [BoundFolder] {
        guard isActive, let project else { return [] }
        return project.roots.compactMap { root in
            folders.first { $0.id == root.id && $0.status != .needsAccess && $0.url != nil }
        }
    }

    func validateActiveTemplateOwners() throws {
        let roots = templateRoots
        for assignment in project?.templateAssignments ?? [] where assignment.state == .active {
            try assignment.validate()
            let owner = assignment.owner
            guard let root = roots.first(where: { $0.id == owner.rootID })?.url else { continue }
            let url = owner.url(in: root)
            // Missing or inaccessible owners await lifecycle recovery. Do not infer a
            // relink, or rewrite their saved reference from incomplete filesystem evidence.
            guard FileManager.default.fileExists(atPath: url.path),
                FileManager.default.isReadableFile(atPath: url.path)
            else { continue }
            // A stored owner must stay within its own root identity, even if another
            // binding grants access to a symlink's outside target.
            guard let canonical = FileReference(rootID: owner.rootID, rootURL: root, url: url) else {
                throw TemplateAssignmentError.invalidReference
            }
            guard canonical == owner else { throw TemplateAssignmentError.invalidReference }
        }
    }

    func templateReference(for url: URL) throws -> FileReference? {
        guard url.isFileURL, !url.pathComponents.contains(".."), !url.pathComponents.contains(".") else {
            throw TemplateAssignmentError.invalidReference
        }
        // Sorting is stable by project order for equivalent-depth aliases.
        let candidates = templateRoots.enumerated().sorted { left, right in
            let leftDepth = left.element.url?.resolvingSymlinksInPath().pathComponents.count ?? 0
            let rightDepth = right.element.url?.resolvingSymlinksInPath().pathComponents.count ?? 0
            return leftDepth == rightDepth ? left.offset < right.offset : leftDepth > rightDepth
        }
        for (_, root) in candidates {
            if let rootURL = root.url,
                let reference = FileReference(rootID: root.id, rootURL: rootURL, url: url)
            {
                return reference
            }
        }
        return nil
    }

    private func templateOwner(for url: URL) throws -> FileReference {
        // Picker URLs may cache directory metadata; query disk again before committing.
        var isDirectory: ObjCBool = false
        guard let reference = try templateReference(for: url),
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { throw TemplateAssignmentError.unavailableFolder }
        try FolderTemplateAssignment.validate(reference.relativePath, allowsRoot: true)
        return reference
    }

    private func templateSourceReference(for url: URL) throws -> FileReference {
        let reference = try eligibleTemplateReference(for: url)
        _ = try savedTemplateBytes(at: url)
        return reference
    }

    func eligibleTemplateReference(for url: URL) throws -> FileReference {
        let resolved = url.resolvingSymlinksInPath()
        guard let reference = try templateReference(for: url),
            ["md", "mdx"].contains(resolved.pathExtension.lowercased())
        else { throw TemplateAssignmentError.ineligibleSource }
        try FolderTemplateAssignment.validate(reference.relativePath, allowsRoot: false)
        do {
            guard try resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw TemplateAssignmentError.ineligibleSource
            }
        } catch let failure as TemplateAssignmentError {
            throw failure
        } catch {
            throw TemplateAssignmentError.sourceUnavailable(error)
        }
        return reference
    }

    func savedTemplateBytes(at url: URL) throws -> Data {
        let bytes: Data
        do {
            let resolved = url.resolvingSymlinksInPath()
            _ = try eligibleTemplateReference(for: resolved)
            // Pin the validated file, rejecting a last-component link substituted before opening.
            let descriptor = open(resolved.path(percentEncoded: false), O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
                throw TemplateAssignmentError.ineligibleSource
            }
            bytes = try handle.readToEnd() ?? Data()
            try handle.close()
            _ = try eligibleTemplateReference(for: url)
        } catch let failure as TemplateAssignmentError {
            throw failure
        } catch {
            throw TemplateAssignmentError.sourceUnavailable(error)
        }
        guard !bytes.contains(0), String(data: bytes, encoding: .utf8) != nil else {
            throw TemplateAssignmentError.unsupportedText
        }
        return bytes
    }
}
