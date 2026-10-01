import Foundation

enum Corpus {
    static let root = Bundle.module.url(forResource: "Corpus", withExtension: nil)!

    struct Example: Decodable {
        let markdown: String
        let example: Int?
        let section: String?
    }

    static func examples(_ name: String) throws -> [Example] {
        let data = try Data(contentsOf: root.appending(path: name))
        return try JSONDecoder().decode([Example].self, from: data)
    }

    static func files(in folder: String) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: root.appending(path: folder), includingPropertiesForKeys: nil
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func text(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }
}
