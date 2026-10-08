import Foundation
import Testing

@testable import GrimoireCore

@Suite struct DiagnosticReportStoreTests {
    func makeStore(_ scratch: Scratch, maxCount: Int = 20) -> DiagnosticReportStore {
        DiagnosticReportStore(folder: scratch.url.appending(path: "Diagnostics"), maxCount: maxCount)
    }

    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func savesTheJSONNamedByTheEndTime() throws {
        let scratch = try Scratch()
        let store = makeStore(scratch)
        let json = Data(#"{"crashDiagnostics":[]}"#.utf8)
        let url = try store.save(json, endDate: start.addingTimeInterval(0.25))
        #expect(url.lastPathComponent == "2027-01-15T08-00-00.250Z.json")
        #expect(try Data(contentsOf: url) == json)
        #expect(store.reports().map(\.lastPathComponent) == [url.lastPathComponent])
    }

    @Test func createsTheFolderOnTheFirstSave() throws {
        let scratch = try Scratch()
        let store = makeStore(scratch)
        #expect(!FileManager.default.fileExists(atPath: store.folder.path(percentEncoded: false)))
        try store.save(Data("{}".utf8), endDate: start)
        #expect(FileManager.default.fileExists(atPath: store.folder.path(percentEncoded: false)))
    }

    @Test func keepsBothPayloadsThatShareAnEndTime() throws {
        let scratch = try Scratch()
        let store = makeStore(scratch)
        let first = try store.save(Data("first".utf8), endDate: start)
        let second = try store.save(Data("second".utf8), endDate: start)
        let third = try store.save(Data("third".utf8), endDate: start)
        #expect(Set([first, second, third]).count == 3)
        #expect(try Data(contentsOf: first) == Data("first".utf8))
        #expect(try Data(contentsOf: second) == Data("second".utf8))
        // Newest first, and a later payload with the same end time counts as newer.
        #expect(store.reports().map(\.lastPathComponent) == [third, second, first].map(\.lastPathComponent))
    }

    @Test func keepsOnlyTheNewestTwenty() throws {
        let scratch = try Scratch()
        let store = makeStore(scratch)
        #expect(store.maxCount == 20)
        var saved: [URL] = []
        for number in 0..<25 {
            saved.append(try store.save(Data("r\(number)".utf8), endDate: start.addingTimeInterval(Double(number))))
        }
        #expect(store.reports().map(\.lastPathComponent) == saved.suffix(20).reversed().map(\.lastPathComponent))
        for url in saved.prefix(5) {
            #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        }
    }

    @Test func prunesByEndTimeNotByTheOrderOfArrival() throws {
        let scratch = try Scratch()
        let store = makeStore(scratch, maxCount: 3)
        // The past reports MetricKit hands over may arrive out of order.
        for number in [5, 1, 4, 2, 3] {
            try store.save(Data("r\(number)".utf8), endDate: start.addingTimeInterval(Double(number)))
        }
        let kept = try store.reports().map { String(decoding: try Data(contentsOf: $0), as: UTF8.self) }
        #expect(kept == ["r5", "r4", "r3"])
    }

    @Test func prunesSharedEndTimeSiblingsOldestFirst() throws {
        let scratch = try Scratch()
        let store = makeStore(scratch, maxCount: 2)
        for name in ["a", "b", "c"] {
            try store.save(Data(name.utf8), endDate: start)
        }
        let kept = try store.reports().map { String(decoding: try Data(contentsOf: $0), as: UTF8.self) }
        #expect(kept == ["c", "b"])
    }

    @Test func leavesOtherFilesAloneWhenPruning() throws {
        let scratch = try Scratch()
        let store = makeStore(scratch, maxCount: 1)
        let note = try scratch.file("Diagnostics/notes.txt", "mine")
        for number in 0..<3 {
            try store.save(Data("r".utf8), endDate: start.addingTimeInterval(Double(number)))
        }
        #expect(store.reports().count == 1)
        #expect(FileManager.default.fileExists(atPath: note.path(percentEncoded: false)))
    }

    @Test func ensureFolderCreatesAnEmptyFolder() throws {
        let scratch = try Scratch()
        let store = makeStore(scratch)
        try store.ensureFolder()
        var isFolder: ObjCBool = false
        let path = store.folder.path(percentEncoded: false)
        #expect(FileManager.default.fileExists(atPath: path, isDirectory: &isFolder))
        #expect(isFolder.boolValue)
        #expect(store.reports().isEmpty)
    }
}
