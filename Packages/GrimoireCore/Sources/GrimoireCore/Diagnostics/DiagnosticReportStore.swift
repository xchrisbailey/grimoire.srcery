import Foundation

/// Keeps the crash and hang diagnostics macOS hands the app, one JSON file per payload,
/// in a folder in Application Support. Only the newest `maxCount` are kept. Nothing here
/// sends a report anywhere.
///
/// A file is named for the payload's end time, `2026-10-08T14-30-00.250Z.json`. A second
/// payload with the same end time takes ` 2`, ` 3`, and so on before `.json`, so no report
/// replaces another.
public final class DiagnosticReportStore: @unchecked Sendable {
    public static let standard = DiagnosticReportStore(
        folder: URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "computer.srcery.grimoire", directoryHint: .isDirectory)
            .appending(path: "Diagnostics", directoryHint: .isDirectory))

    public let folder: URL
    public var maxCount = 20

    /// Serializes saves, so two payloads arriving together don't pick the same name.
    private let lock = NSLock()

    public init(folder: URL) {
        self.folder = folder
    }

    /// Writes `json` as the report for a payload that ended at `endDate`, then removes the
    /// oldest reports beyond `maxCount`. Returns the file it wrote.
    @discardableResult
    public func save(_ json: Data, endDate: Date) throws -> URL {
        try lock.withLock {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stem = Self.stamp(endDate)
            var copy = 1
            var url = folder.appending(path: Self.fileName(stem: stem, copy: copy))
            while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                copy += 1
                url = folder.appending(path: Self.fileName(stem: stem, copy: copy))
            }
            try json.write(to: url, options: .atomic)
            prune()
            return url
        }
    }

    /// The saved reports, newest first.
    public func reports() -> [URL] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url in Self.parse(url).map { (url, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Makes sure the folder exists, so there is something to show when no report has arrived.
    public func ensureFolder() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func prune() {
        for url in reports().dropFirst(maxCount) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - File names

    /// The end time in UTC to the millisecond, with no colons, which Finder shows as slashes.
    static func stamp(_ date: Date) -> String {
        date.formatted(
            Date.VerbatimFormatStyle(
                format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)T\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))-\(minute: .twoDigits)-\(second: .twoDigits).\(secondFraction: .fractional(3))Z",
                timeZone: .gmt, calendar: Calendar(identifier: .gregorian)))
    }

    static func fileName(stem: String, copy: Int) -> String {
        copy == 1 ? "\(stem).json" : "\(stem) \(copy).json"
    }

    /// Orders reports: the end time first, then which of the payloads sharing it came later.
    struct Order: Comparable {
        var stem: String
        var copy: Int

        static func < (lhs: Order, rhs: Order) -> Bool {
            (lhs.stem, lhs.copy) < (rhs.stem, rhs.copy)
        }
    }

    static func parse(_ url: URL) -> Order? {
        guard url.pathExtension == "json" else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: " ", maxSplits: 1)
        guard let first = parts.first, first.hasSuffix("Z") else { return nil }
        if parts.count == 1 { return Order(stem: String(first), copy: 1) }
        guard let copy = Int(parts[1]), copy > 1 else { return nil }
        return Order(stem: String(first), copy: copy)
    }
}
