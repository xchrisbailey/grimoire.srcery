import Foundation

/// An exact folder's project-local choice. This record does not perform ancestor lookup.
public struct FolderTemplateAssignment: Codable, Hashable, Sendable {
    public enum Choice: Hashable, Sendable {
        case useSource(FileReference)
        case noTemplate
    }

    public enum State: String, Codable, Sendable {
        case active, unresolved
    }

    public var owner: FileReference
    public var choice: Choice
    public var state: State

    public init(owner: FileReference, choice: Choice, state: State = .active) {
        self.owner = owner
        self.choice = choice
        self.state = state
    }

    private enum CodingKeys: String, CodingKey { case owner, mode, source, state }
    private enum Mode: String, Codable { case useSource, noTemplate }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        owner = try container.decode(FileReference.self, forKey: .owner)
        state = try container.decode(State.self, forKey: .state)
        switch try container.decode(Mode.self, forKey: .mode) {
        case .useSource:
            choice = .useSource(try container.decode(FileReference.self, forKey: .source))
        case .noTemplate:
            guard !container.contains(.source) else { throw TemplateAssignmentError.invalidReference }
            choice = .noTemplate
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(owner, forKey: .owner)
        try container.encode(state, forKey: .state)
        switch choice {
        case .useSource(let source):
            try container.encode(Mode.useSource, forKey: .mode)
            try container.encode(source, forKey: .source)
        case .noTemplate:
            try container.encode(Mode.noTemplate, forKey: .mode)
        }
    }

    func validate() throws {
        try Self.validate(owner.relativePath, allowsRoot: true)
        if case .useSource(let source) = choice {
            try Self.validate(source.relativePath, allowsRoot: false)
        }
    }

    static func validate(_ path: String, allowsRoot: Bool) throws {
        if path.isEmpty, allowsRoot { return }
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
            path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
                !$0.isEmpty && $0 != "." && $0 != ".."
            })
        else { throw TemplateAssignmentError.invalidReference }
    }

    static func validate(_ assignments: [Self]) throws {
        var choices: [FileReference: Self] = [:]
        for assignment in assignments {
            try assignment.validate()
            if let existing = choices[assignment.owner], existing != assignment {
                throw TemplateAssignmentError.conflictingChoices
            }
            choices[assignment.owner] = assignment
        }
    }
}

public enum TemplateAssignmentError: Error, LocalizedError {
    case invalidReference, conflictingChoices, unavailableFolder, ineligibleSource, unsupportedText
    case sourceUnavailable(any Error)
    case recoveryChanged

    public var errorDescription: String? {
        switch self {
        case .recoveryChanged:
            String(localized: "Folder template recovery changed. Review the folder and configuration, then retry.")
        case .invalidReference:
            String(localized: "Invalid content template reference. Repair the project settings and retry.")
        case .conflictingChoices:
            String(localized: "Conflicting folder template choices. Repair the project settings and retry.")
        case .unavailableFolder:
            String(localized: "The owning folder is unavailable. Restore bound-folder access and retry.")
        case .ineligibleSource:
            String(
                localized:
                    "Choose a Markdown file in this project’s accessible bound folders. For links, bind the target.")
        case .unsupportedText:
            String(localized: "Use UTF-8 text without NUL bytes. Repair the template source or choose another source.")
        case .sourceUnavailable(let error):
            String(localized: "The template source couldn’t be read. Restore access or choose another source.")
                + "\n" + error.localizedDescription
        }
    }
}
