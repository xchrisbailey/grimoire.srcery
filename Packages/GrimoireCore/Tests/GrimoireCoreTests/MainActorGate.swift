import Testing

/// Swift Testing starts all ~400 tests at once. The `@MainActor` ones queue their synchronous
/// setup (project saves, bookmarks, FSEvents streams) on the one main thread in arrival order,
/// so a test's first poll in `until` sat behind the whole backlog: in a passing run 470 of 474
/// waits took over a second and a 20ms sleep resumed up to 3.6s late, within reach of the 5s
/// deadline. Admitting a few cases at a time keeps each wait short without changing what any
/// test asserts.
actor MainActorGate {
    static let shared = MainActorGate(width: 4)

    private var free: Int
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(width: Int) {
        free = width
    }

    func enter() async {
        if free > 0 {
            free -= 1
        } else {
            await withCheckedContinuation { waiting.append($0) }
        }
    }

    func leave() {
        if waiting.isEmpty {
            free += 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}

struct MainActorGateTrait: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        guard testCase != nil else { return try await function() }
        await MainActorGate.shared.enter()
        do {
            try await function()
        } catch {
            await MainActorGate.shared.leave()
            throw error
        }
        await MainActorGate.shared.leave()
    }
}

extension Trait where Self == MainActorGateTrait {
    /// Limits how many cases of this suite run at once alongside the other gated suites.
    static var mainActorGate: Self { MainActorGateTrait() }
}
