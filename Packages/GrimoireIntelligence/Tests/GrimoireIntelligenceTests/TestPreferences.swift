import Foundation

final class TestPreferences: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    init() {
        super.init(suiteName: "grimoire-tests-\(UUID())")!
    }

    func cleanUp() {
        lock.withLock { values.removeAll() }
    }

    override func set(_ value: Any?, forKey key: String) {
        // Persistent domains leave plists; the argument domain is shared across fixtures.
        lock.withLock { values[key] = value }
    }

    override func object(forKey key: String) -> Any? {
        lock.withLock { values[key] } ?? super.object(forKey: key)
    }

    override func removeObject(forKey key: String) {
        set(nil, forKey: key)
    }
}
