import Compression
import Foundation

/// Reads files out of a zip archive in memory, enough for a VS Code `.vsix`: stored and
/// deflated entries, no encryption, no zip64.
public struct ZipArchive: Sendable {
    public struct Entry: Sendable {
        public var path: String
        var method: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
    }

    public enum ZipError: Error, Equatable {
        case notAZip
        case unsupported(String)
        case corrupt(String)
    }

    private let data: Data
    public let entries: [Entry]

    public init(data: Data) throws {
        self.data = data
        entries = try Self.readCentralDirectory(data)
    }

    public var paths: [String] { entries.map(\.path) }

    /// The contents of the entry at `path`, or nil when there's no such entry.
    public func contents(of path: String) throws -> Data? {
        guard let entry = entries.first(where: { $0.path == path }) else { return nil }
        return try contents(of: entry)
    }

    public func contents(of entry: Entry) throws -> Data {
        let header = entry.localHeaderOffset
        guard data.uint32(at: header) == 0x0403_4b50 else { throw ZipError.corrupt(entry.path) }
        let nameLength = Int(data.uint16(at: header + 26))
        let extraLength = Int(data.uint16(at: header + 28))
        let start = header + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= data.count else { throw ZipError.corrupt(entry.path) }
        let compressed = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + entry.compressedSize))
        switch entry.method {
        case 0:
            return compressed
        case 8:
            return try Self.inflate(compressed, size: entry.uncompressedSize, path: entry.path)
        default:
            throw ZipError.unsupported(entry.path)
        }
    }

    // MARK: - Reading

    private static func readCentralDirectory(_ data: Data) throws -> [Entry] {
        // The end-of-central-directory record sits in the last 64 KB (it can carry a comment).
        guard data.count >= 22 else { throw ZipError.notAZip }
        let lowest = max(0, data.count - 22 - 65_535)
        var end: Int?
        var offset = data.count - 22
        while offset >= lowest {
            if data.uint32(at: offset) == 0x0605_4b50 {
                end = offset
                break
            }
            offset -= 1
        }
        guard let end else { throw ZipError.notAZip }
        let count = Int(data.uint16(at: end + 10))
        var cursor = Int(data.uint32(at: end + 16))
        var entries: [Entry] = []
        entries.reserveCapacity(count)
        for _ in 0..<count {
            guard cursor + 46 <= data.count, data.uint32(at: cursor) == 0x0201_4b50 else {
                throw ZipError.corrupt("central directory")
            }
            let flags = data.uint16(at: cursor + 8)
            let nameLength = Int(data.uint16(at: cursor + 28))
            let extraLength = Int(data.uint16(at: cursor + 30))
            let commentLength = Int(data.uint16(at: cursor + 32))
            guard cursor + 46 + nameLength <= data.count else { throw ZipError.corrupt("central directory") }
            let nameData = data.subdata(
                in: (data.startIndex + cursor + 46)..<(data.startIndex + cursor + 46 + nameLength))
            let path = String(decoding: nameData, as: UTF8.self)
            if flags & 1 != 0 { throw ZipError.unsupported(path) }
            entries.append(
                Entry(
                    path: path, method: data.uint16(at: cursor + 10),
                    compressedSize: Int(data.uint32(at: cursor + 20)),
                    uncompressedSize: Int(data.uint32(at: cursor + 24)),
                    localHeaderOffset: Int(data.uint32(at: cursor + 42))))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// Raw DEFLATE, which is what Compression calls `COMPRESSION_ZLIB`.
    private static func inflate(_ compressed: Data, size: Int, path: String) throws -> Data {
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { destination in
            compressed.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, size,
                    source.bindMemory(to: UInt8.self).baseAddress!, compressed.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ZipError.corrupt(path) }
        return output
    }
}

extension Data {
    fileprivate func uint16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        let base = startIndex + offset
        return UInt16(self[base]) | UInt16(self[base + 1]) << 8
    }

    fileprivate func uint32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        let base = startIndex + offset
        return UInt32(self[base]) | UInt32(self[base + 1]) << 8 | UInt32(self[base + 2]) << 16
            | UInt32(self[base + 3]) << 24
    }
}
