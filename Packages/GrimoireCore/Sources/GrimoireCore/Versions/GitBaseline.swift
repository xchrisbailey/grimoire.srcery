import Compression
import Foundation

/// Reads a file's last committed text straight from the repository's `.git` folder (loose
/// objects and packs), so it works inside the sandbox without running `git`.
public enum GitBaseline {
    /// The text of `url` as of `HEAD`, or nil when it isn't in a git repository or isn't
    /// committed.
    public static func committedText(of url: URL) -> String? {
        guard let (gitDir, path) = locate(url), let repo = GitRepository(gitDir: gitDir),
            let commit = repo.resolveHEAD(), let blob = repo.blob(at: path, inCommit: commit)
        else { return nil }
        return String(decoding: blob, as: UTF8.self)
    }

    /// The `.git` folder above `url`, and `url`'s path inside the work tree.
    static func locate(_ url: URL) -> (URL, [String])? {
        let file = url.standardizedFileURL.resolvingSymlinksInPath()
        var folder = file.deletingLastPathComponent()
        var components = [file.lastPathComponent]
        let manager = FileManager.default
        while folder.pathComponents.count > 1 {
            let git = folder.appending(path: ".git")
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: git.path(percentEncoded: false), isDirectory: &isDirectory),
                isDirectory.boolValue
            {
                return (git, components)
            }
            components.insert(folder.lastPathComponent, at: 0)
            folder = folder.deletingLastPathComponent()
        }
        return nil
    }
}

// MARK: - Repository

struct GitRepository {
    let gitDir: URL
    let packs: [GitPack]

    init?(gitDir: URL) {
        self.gitDir = gitDir
        let packDir = gitDir.appending(path: "objects/pack")
        let files =
            (try? FileManager.default.contentsOfDirectory(at: packDir, includingPropertiesForKeys: nil)) ?? []
        packs = files.filter { $0.pathExtension == "idx" }.compactMap(GitPack.init(index:))
    }

    func resolveHEAD() -> String? {
        guard let head = try? String(contentsOf: gitDir.appending(path: "HEAD"), encoding: .utf8) else {
            return nil
        }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("ref: ") else { return trimmed.count == 40 ? trimmed : nil }
        return resolve(ref: String(trimmed.dropFirst(5)))
    }

    func resolve(ref: String) -> String? {
        if let loose = try? String(contentsOf: gitDir.appending(path: ref), encoding: .utf8) {
            return loose.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let packed = try? String(contentsOf: gitDir.appending(path: "packed-refs"), encoding: .utf8) else {
            return nil
        }
        for line in packed.split(whereSeparator: \.isNewline) where line.hasSuffix(" " + ref) {
            return String(line.prefix(40))
        }
        return nil
    }

    /// The blob at `path` in commit `sha`.
    func blob(at path: [String], inCommit sha: String) -> Data? {
        guard let commit = object(sha), commit.type == .commit,
            let header = String(data: commit.data.prefix(200), encoding: .utf8),
            header.hasPrefix("tree "), var current = Optional(String(header.dropFirst(5).prefix(40)))
        else { return nil }
        for (position, name) in path.enumerated() {
            guard let tree = object(current), tree.type == .tree, let entry = Self.entry(named: name, in: tree.data)
            else { return nil }
            current = entry
            if position == path.count - 1 {
                guard let blob = object(current), blob.type == .blob else { return nil }
                return blob.data
            }
        }
        return nil
    }

    /// The object id a tree lists for `name`.
    static func entry(named name: String, in tree: Data) -> String? {
        let bytes = [UInt8](tree)
        var index = 0
        while index < bytes.count {
            guard let space = bytes[index...].firstIndex(of: 0x20), let zero = bytes[space...].firstIndex(of: 0)
            else { return nil }
            let entryName = String(decoding: bytes[(space + 1)..<zero], as: UTF8.self)
            let shaStart = zero + 1
            guard shaStart + 20 <= bytes.count else { return nil }
            if entryName == name { return bytes[shaStart..<(shaStart + 20)].hex }
            index = shaStart + 20
        }
        return nil
    }

    func object(_ sha: String) -> GitObject? {
        let loose = gitDir.appending(path: "objects/\(sha.prefix(2))/\(sha.dropFirst(2))")
        if let data = try? Data(contentsOf: loose), let inflated = GitZlib.inflate(data) {
            return GitObject(loose: inflated)
        }
        for pack in packs {
            if let offset = pack.offset(of: sha) { return pack.object(at: offset, repository: self) }
        }
        return nil
    }
}

// MARK: - Objects

struct GitObject {
    enum Kind: Int {
        case commit = 1, tree = 2, blob = 3, tag = 4
    }

    var type: Kind
    var data: Data

    init(type: Kind, data: Data) {
        self.type = type
        self.data = data
    }

    /// A loose object: `type size\0content`.
    init?(loose: Data) {
        guard let zero = loose.firstIndex(of: 0),
            let header = String(data: loose[loose.startIndex..<zero], encoding: .utf8)
        else { return nil }
        let kinds: [String: Kind] = ["commit": .commit, "tree": .tree, "blob": .blob, "tag": .tag]
        guard let name = header.split(separator: " ").first, let kind = kinds[String(name)] else { return nil }
        self.init(type: kind, data: Data(loose[(zero + 1)...]))
    }
}

/// One pack and its version 2 index.
struct GitPack {
    let index: Data
    let pack: Data

    init?(index url: URL) {
        guard let index = try? Data(contentsOf: url, options: .mappedIfSafe),
            let pack = try? Data(
                contentsOf: url.deletingPathExtension().appendingPathExtension("pack"), options: .mappedIfSafe),
            index.count > 8, index.prefix(4) == Data([0xFF, 0x74, 0x4F, 0x63])
        else { return nil }
        self.index = index
        self.pack = pack
    }

    private var count: Int { Int(index.bigEndian32(at: 8 + 255 * 4)) }

    func offset(of sha: String) -> Int? {
        guard let target = Data(hex: sha), target.count == 20 else { return nil }
        let first = Int(target[0])
        let lower = first == 0 ? 0 : Int(index.bigEndian32(at: 8 + (first - 1) * 4))
        let upper = Int(index.bigEndian32(at: 8 + first * 4))
        let names = 8 + 256 * 4
        var low = lower
        var high = upper - 1
        while low <= high {
            let mid = (low + high) / 2
            let start = names + mid * 20
            let candidate = index[(index.startIndex + start)..<(index.startIndex + start + 20)]
            if candidate.elementsEqual(target) {
                return entryOffset(mid)
            } else if candidate.lexicographicallyPrecedes(target) {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return nil
    }

    private func entryOffset(_ position: Int) -> Int {
        let offsets = 8 + 256 * 4 + count * 24
        let small = index.bigEndian32(at: offsets + position * 4)
        guard small & 0x8000_0000 != 0 else { return Int(small) }
        let large = offsets + count * 4 + Int(small & 0x7FFF_FFFF) * 8
        return Int(index.bigEndian32(at: large)) << 32 | Int(index.bigEndian32(at: large + 4))
    }

    func object(at offset: Int, repository: GitRepository, depth: Int = 0) -> GitObject? {
        guard depth < 50, offset < pack.count else { return nil }
        var cursor = offset
        var byte = Int(pack[pack.startIndex + cursor])
        cursor += 1
        let type = (byte >> 4) & 7
        var size = byte & 0x0F
        var shift = 4
        while byte & 0x80 != 0 {
            byte = Int(pack[pack.startIndex + cursor])
            cursor += 1
            size |= (byte & 0x7F) << shift
            shift += 7
        }
        switch type {
        case 1...4:
            guard let kind = GitObject.Kind(rawValue: type),
                let data = GitZlib.inflate(pack.suffix(from: pack.startIndex + cursor), size: size)
            else { return nil }
            return GitObject(type: kind, data: data)
        case 6:
            // Offset delta: the base sits a variable-length distance back in this pack.
            byte = Int(pack[pack.startIndex + cursor])
            cursor += 1
            var distance = byte & 0x7F
            while byte & 0x80 != 0 {
                byte = Int(pack[pack.startIndex + cursor])
                cursor += 1
                distance = ((distance + 1) << 7) | (byte & 0x7F)
            }
            guard let base = object(at: offset - distance, repository: repository, depth: depth + 1),
                let delta = GitZlib.inflate(pack.suffix(from: pack.startIndex + cursor), size: size),
                let data = GitDelta.apply(delta, to: base.data)
            else { return nil }
            return GitObject(type: base.type, data: data)
        case 7:
            let baseSHA = pack[(pack.startIndex + cursor)..<(pack.startIndex + cursor + 20)].hex
            cursor += 20
            guard let base = repository.object(baseSHA),
                let delta = GitZlib.inflate(pack.suffix(from: pack.startIndex + cursor), size: size),
                let data = GitDelta.apply(delta, to: base.data)
            else { return nil }
            return GitObject(type: base.type, data: data)
        default:
            return nil
        }
    }
}

/// Git's delta format: the base and result sizes, then copy and insert instructions.
enum GitDelta {
    static func apply(_ delta: Data, to base: Data) -> Data? {
        let bytes = [UInt8](delta)
        var cursor = 0
        func varint() -> Int {
            var value = 0
            var shift = 0
            while cursor < bytes.count {
                let byte = Int(bytes[cursor])
                cursor += 1
                value |= (byte & 0x7F) << shift
                shift += 7
                if byte & 0x80 == 0 { break }
            }
            return value
        }
        guard varint() == base.count else { return nil }
        let resultSize = varint()
        var result = Data(capacity: resultSize)
        let baseBytes = [UInt8](base)
        while cursor < bytes.count {
            let instruction = Int(bytes[cursor])
            cursor += 1
            if instruction & 0x80 != 0 {
                var offset = 0
                var size = 0
                for bit in 0..<4 where instruction & (1 << bit) != 0 {
                    offset |= Int(bytes[cursor]) << (8 * bit)
                    cursor += 1
                }
                for bit in 0..<3 where instruction & (1 << (4 + bit)) != 0 {
                    size |= Int(bytes[cursor]) << (8 * bit)
                    cursor += 1
                }
                if size == 0 { size = 0x10000 }
                guard offset + size <= baseBytes.count else { return nil }
                result.append(contentsOf: baseBytes[offset..<(offset + size)])
            } else if instruction > 0 {
                guard cursor + instruction <= bytes.count else { return nil }
                result.append(contentsOf: bytes[cursor..<(cursor + instruction)])
                cursor += instruction
            } else {
                return nil
            }
        }
        return result.count == resultSize ? result : nil
    }
}

/// zlib streams as git writes them: a 2-byte header, raw deflate, a checksum.
enum GitZlib {
    static func inflate(_ data: Data, size: Int? = nil) -> Data? {
        guard data.count > 2 else { return size == 0 ? Data() : nil }
        let body = data.dropFirst(2)
        var capacity = max(size ?? data.count * 4, 64)
        while true {
            var output = Data(count: capacity)
            let written = output.withUnsafeMutableBytes { destination in
                body.withUnsafeBytes { source in
                    compression_decode_buffer(
                        destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                        source.bindMemory(to: UInt8.self).baseAddress!, body.count, nil, COMPRESSION_ZLIB)
                }
            }
            if let size {
                return written == size ? output.prefix(size) : (size == 0 ? Data() : nil)
            }
            // Without a known size, a full buffer may mean it was cut short; try bigger.
            if written < capacity { return written > 0 ? output.prefix(written) : nil }
            capacity *= 4
            if capacity > 512 * 1024 * 1024 { return nil }
        }
    }
}

extension Data {
    fileprivate func bigEndian32(at offset: Int) -> UInt32 {
        let base = startIndex + offset
        return UInt32(self[base]) << 24 | UInt32(self[base + 1]) << 16 | UInt32(self[base + 2]) << 8
            | UInt32(self[base + 3])
    }

    fileprivate init?(hex: String) {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}

extension Collection where Element == UInt8 {
    fileprivate var hex: String { map { String(format: "%02x", $0) }.joined() }
}
