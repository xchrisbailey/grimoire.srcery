import Foundation
import Testing

@testable import GrimoireCore

/// What `beta3-shape.json` holds: the last release's stored values and keys.
struct StoredShapeSnapshot: Decodable {
    struct Record: Decodable {
        /// Keys the release's decoder needs; writing without one makes it fail.
        var required: [String]
        /// Keys it reads when they are there.
        var optional: [String]
        /// Keys this build writes that the release's decoder never reads.
        var ignoredByRelease: [String]
    }

    var release: String
    var enums: [String: [String]]
    var records: [String: Record]
}

/// Guards what an installed build can still read after a user rolls back to the last release.
///
/// `Fixtures/StoredShape/beta3-shape.json` lists every stored enum value and key that
/// v1.0.0-beta.3 wrote or read, and `Fixtures/StoredShape/beta3/` holds files in the shape it
/// wrote. Both come from that tag's `Project.swift`, `ProjectStore.swift`, `Preferences.swift`
/// and `VersionStore.swift`. After a release, repoint them at the new tag.
@Suite struct StoredShapeTests {
    // MARK: Snapshot

    static let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
        .appending(path: "StoredShape", directoryHint: .isDirectory)

    static func snapshot() throws -> StoredShapeSnapshot {
        let data = try Data(contentsOf: fixtures.appending(path: "beta3-shape.json"))
        return try JSONDecoder().decode(StoredShapeSnapshot.self, from: data)
    }

    // `allCases` picks up a new case without anyone remembering to list it here.
    static let currentEnums: [String: [String]] = [
        "Version.Reason": Version.Reason.allCases.map(\.rawValue),
        "ProjectKind": ProjectKind.allCases.map(\.rawValue),
        "ProjectColor": ProjectColor.allCases.map(\.rawValue),
        "ImageLocation": ImageLocation.allCases.map(\.rawValue),
    ]

    static let consequences: [String: String] = [
        "Version.Reason":
            "VersionStore.load treats a decode failure as empty history and the next keep overwrites the index",
        "ProjectKind":
            "it reads an unknown kind as a standard project, so the project loses its kind on the next save",
        "ProjectColor":
            "projects.json fails to decode, its ProjectLibrary starts empty, and the next change overwrites the file",
        "ImageLocation":
            "projects.json fails to decode, its ProjectLibrary starts empty, and the next change overwrites the file",
    ]

    // MARK: Enums

    @Test func storedEnumsKeepTheValuesTheLastReleaseCanRead() throws {
        let snapshot = try Self.snapshot()
        #expect(Set(snapshot.enums.keys) == Set(Self.currentEnums.keys), "Every stored enum needs a snapshot entry.")
        for (name, released) in snapshot.enums.sorted(by: { $0.key < $1.key }) {
            let current = Set(Self.currentEnums[name] ?? [])
            let added = current.subtracting(released).sorted()
            let removed = Set(released).subtracting(current).sorted()
            if !added.isEmpty {
                Issue.record(
                    """
                    \(name) gained stored value(s) \(added). \(snapshot.release) cannot decode them: \
                    \(Self.consequences[name] ?? "it fails to read the file"). Rolling back loses data. \
                    If this is deliberate, add the value to \(name) in Fixtures/StoredShape/beta3-shape.json and put \
                    a rollback note in the release notes.
                    """)
            }
            if !removed.isEmpty {
                Issue.record(
                    """
                    \(name) no longer reads \(removed), which \(snapshot.release) wrote. \
                    Files saved by that release would fail to load here.
                    """)
            }
        }
    }

    // MARK: Keys

    /// A fully populated project and version index, written the way the app writes them, and the
    /// keys found in each kind of record.
    static func writtenKeys() throws -> [String: Set<String>] {
        let scratch = try Scratch()
        let root = FolderRoot(name: "Notes", alias: "Field notes", bookmark: Data([1]), lastKnownPath: "/Notes")
        let reference = FileReference(rootID: root.id, relativePath: "posts")
        let project = Project(
            name: "Spellbook",
            roots: [root],
            looseFiles: [LooseFile(name: "todo.md", bookmark: Data([2]), lastKnownPath: "/todo.md")],
            kind: .unsorted,
            lastOpenedFile: reference,
            expandedFolders: [reference],
            overrides: ProjectOverrides(fileExtensions: ["md"], imageLocation: .projectFolder, intelligenceOff: true),
            dictionary: ["mdx"],
            templateAssignments: [
                FolderTemplateAssignment(
                    owner: reference, choice: .useSource(FileReference(rootID: root.id, relativePath: "t/post.md")))
            ])
        let projectsFile = scratch.url.appending(path: "projects.json")
        try ProjectStore(fileURL: projectsFile).save([project])

        var keys: [String: Set<String>] = [:]
        func add(_ name: String, _ object: Any?) {
            if let dictionary = object as? [String: Any] { keys[name, default: []].formUnion(dictionary.keys) }
        }
        let top = try JSONSerialization.jsonObject(with: Data(contentsOf: projectsFile)) as? [String: Any]
        add("projects.json", top)
        for case let project as [String: Any] in top?["projects"] as? [Any] ?? [] {
            add("Project", project)
            for root in project["roots"] as? [Any] ?? [] { add("FolderRoot", root) }
            for file in project["looseFiles"] as? [Any] ?? [] { add("LooseFile", file) }
            add("FileReference", project["lastOpenedFile"])
            for folder in project["expandedFolders"] as? [Any] ?? [] { add("FileReference", folder) }
            add("ProjectOverrides", project["overrides"])
        }

        let versions = VersionStore(folder: scratch.url.appending(path: "Versions"))
        versions.keep("text", of: scratch.url.appending(path: "draft.md"), reason: .edit)
        let index = try FileManager.default.subpathsOfDirectory(
            atPath: scratch.url.appending(path: "Versions").path(percentEncoded: false)
        )
        .first { $0.hasSuffix("index.json") }
        let indexFile = try #require(index.map { scratch.url.appending(path: "Versions").appending(path: $0) })
        let indexObject = try JSONSerialization.jsonObject(with: Data(contentsOf: indexFile)) as? [String: Any]
        add("Versions/<hash>/index.json", indexObject)
        for version in indexObject?["versions"] as? [Any] ?? [] { add("Version", version) }
        return keys
    }

    @Test func storedKeysStayReadableByTheLastRelease() throws {
        let snapshot = try Self.snapshot()
        let written = try Self.writtenKeys()
        #expect(Set(snapshot.records.keys) == Set(written.keys), "Every stored record needs a snapshot entry.")
        for (name, record) in snapshot.records.sorted(by: { $0.key < $1.key }) {
            let keys = written[name] ?? []
            let known = Set(record.required + record.optional + record.ignoredByRelease)
            let dropped = Set(record.required).subtracting(keys).sorted()
            let unlisted = keys.subtracting(known).sorted()
            if !dropped.isEmpty {
                Issue.record(
                    """
                    \(name) no longer writes \(dropped), which \(snapshot.release) requires. It cannot decode the \
                    file, and rolling back loses data: an index it cannot read counts as empty and the next save \
                    overwrites it.
                    """)
            }
            if !unlisted.isEmpty {
                Issue.record(
                    """
                    \(name) now writes \(unlisted), which \(snapshot.release) does not read. It still loads the \
                    file, but its next save drops those keys, so rolling back loses them. If this is deliberate, \
                    list them under ignoredByRelease for \(name) in Fixtures/StoredShape/beta3-shape.json and put a \
                    rollback note in the release notes.
                    """)
            }
        }
    }

    // MARK: Files from the last release

    private func copy(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
    }

    /// Every file under `folder` by relative path, to prove a load wrote nothing.
    private func contents(of folder: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: folder.path(percentEncoded: false)) {
            var isDirectory: ObjCBool = false
            let url = folder.appending(path: path)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
                !isDirectory.boolValue
            else { continue }
            result[path] = try Data(contentsOf: url)
        }
        return result
    }

    @MainActor @Test func loadsABeta3ProjectsFileWithoutChangingIt() throws {
        let scratch = try Scratch()
        let file = scratch.url.appending(path: "projects.json")
        try copy(Self.fixtures.appending(path: "beta3/projects.json"), to: file)
        let before = try Data(contentsOf: file)

        let projects = try ProjectStore(fileURL: file).load()
        let library = ProjectLibrary(store: ProjectStore(fileURL: file))
        #expect(library.loadError == nil)
        #expect(library.projects == projects)
        #expect(try Data(contentsOf: file) == before)

        let rootA = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let rootB = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        #expect(projects.count == 2)
        let spellbook = projects[0]
        #expect(spellbook.id == UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001"))
        #expect(spellbook.name == "Spellbook")
        #expect(spellbook.icon == "wand.and.stars")
        #expect(spellbook.color == .lavender)
        #expect(spellbook.kind == .standard)
        #expect(spellbook.roots.map(\.id) == [rootA, rootB])
        #expect(spellbook.roots.map(\.displayName) == ["Field notes", "Drafts"])
        #expect(spellbook.roots[0].alias == "Field notes")
        #expect(spellbook.roots[0].bookmark == Data("bookmark-a".utf8))
        #expect(spellbook.roots[0].lastKnownPath == "/Users/tester/Notes")
        #expect(spellbook.roots[1].alias == nil)
        #expect(spellbook.looseFiles.count == 1)
        #expect(spellbook.looseFiles[0].name == "todo.md")
        #expect(spellbook.looseFiles[0].bookmark == Data("bookmark-c".utf8))
        #expect(spellbook.looseFiles[0].lastKnownPath == "/Users/tester/Desktop/todo.md")
        #expect(spellbook.lastOpenedFile == FileReference(rootID: rootA, relativePath: "posts/first.md"))
        #expect(
            spellbook.expandedFolders
                == [
                    FileReference(rootID: rootA, relativePath: ""), FileReference(rootID: rootA, relativePath: "posts"),
                ])
        #expect(
            spellbook.overrides
                == ProjectOverrides(
                    fileExtensions: ["md", "mdx", "markdown"], imageLocation: .projectFolder, intelligenceOff: true))
        #expect(spellbook.dictionary == ["Grimoire", "mdx"])
        #expect(spellbook.templateAssignments.isEmpty)

        // The oldest shape: every optional key absent.
        let unsorted = projects[1]
        #expect(unsorted.kind == .unsorted)
        #expect(unsorted.color == .quote)
        #expect(unsorted.roots.isEmpty)
        #expect(unsorted.lastOpenedFile == nil)
        #expect(unsorted.overrides == ProjectOverrides())
        #expect(unsorted.dictionary.isEmpty)
    }

    @Test func loadsABeta3VersionIndexWithoutChangingIt() throws {
        let scratch = try Scratch()
        let folder = scratch.url.appending(path: "Versions", directoryHint: .isDirectory)
        try copy(Self.fixtures.appending(path: "beta3/Versions"), to: folder)
        let before = try contents(of: folder)
        #expect(before.count == 7)

        // The folder name is a hash of this path, as it was in beta.3.
        let draft = URL(filePath: "/Users/tester/Notes/draft.md")
        let store = VersionStore(folder: folder)
        let versions = store.versions(of: draft)

        #expect(
            versions.map(\.reason) == [.intelligence, .restore, .conflict, .externalChange, .replaceAll, .edit])
        #expect(versions.map(\.size) == [40, 35, 36, 42, 38, 32])
        #expect(versions.first?.id == UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000001"))
        #expect(versions.first?.date == Date(timeIntervalSince1970: 1_770_350_706))
        #expect(versions.last?.date == Date(timeIntervalSince1970: 1_769_918_706))
        #expect(store.text(of: versions[3], for: draft) == "# Draft\n\nVersion kept for externalChange.\n")
        #expect(try contents(of: folder) == before)
    }
}
