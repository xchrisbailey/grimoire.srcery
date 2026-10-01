import Foundation
import GrimoireCore
import Testing

@testable import GrimoireIntelligence

/// Whether the on-device model can run here; tests that need it are skipped otherwise.
let modelIsReady = IntelligenceService.modelStatus == .ready

@MainActor @Suite struct IntelligenceSettingsTests {
    func makeService() -> (IntelligenceService, Preferences) {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "grimoire-tests-\(UUID().uuidString)")!)
        return (IntelligenceService(preferences: preferences), preferences)
    }

    @Test func settingsCanTurnItOff() {
        let (service, preferences) = makeService()
        preferences.intelligenceEnabled = false
        #expect(service.status(for: nil) == .turnedOff)
        preferences.intelligenceEnabled = true
        var project = Project(name: "Private")
        project.overrides.intelligenceOff = true
        #expect(service.status(for: project) == .turnedOffForProject)
        #expect(service.status(for: nil) == IntelligenceService.modelStatus)
    }

    @Test func everyStatusButReadyExplainsItself() {
        let statuses: [IntelligenceStatus] = [
            .turnedOff, .turnedOffForProject, .deviceNotEligible, .appleIntelligenceOff, .downloading,
        ]
        #expect(statuses.allSatisfy { $0.message?.isEmpty == false })
        #expect(IntelligenceStatus.ready.message == nil)
    }

    @Test(.enabled(if: modelIsReady)) func longPromptsNeedPermissionForTheCloud() async throws {
        let (service, preferences) = makeService()
        #expect(try await service.route(forTokens: 100) == .onDevice)
        await #expect(throws: IntelligenceError.tooLong) { try await service.route(forTokens: 50_000) }
        preferences.allowsPrivateCloud = true
        let route = try? await service.route(forTokens: 10_000)
        #expect(route == nil || route == .privateCloud)
    }
}

/// A small evaluation set for the foundation: each prompt runs on the real on-device
/// model and is checked loosely, so model updates that break a feature show up.
@MainActor @Suite(.enabled(if: modelIsReady), .serialized) struct IntelligenceEvaluations {
    @Test func streamsGrowingText() async throws {
        let request = IntelligenceRequest(
            instructions: "You write short plain sentences.", text: "Describe ink in one sentence.", temperature: 0)
        var snapshots: [String] = []
        for try await text in IntelligenceService.shared.stream(request) { snapshots.append(text) }
        let last = try #require(snapshots.last)
        #expect(!last.isEmpty)
        #expect(zip(snapshots, snapshots.dropFirst()).allSatisfy { $1.hasPrefix($0) || $1.count >= $0.count })
    }

    @Test func cancellingStopsTheStream() async throws {
        let request = IntelligenceRequest(
            instructions: "You write long detailed essays.", text: "Write a long essay about the history of ink.")
        let task = Task { @MainActor in
            var count = 0
            for try await _ in IntelligenceService.shared.stream(request) { count += 1 }
            return count
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        _ = try await task.value
    }
}

#if os(macOS)
import AppKit
import GrimoireEditor

/// The "done when" for #18: a response from the real model streams into the editor and is
/// kept as one undo step.
@MainActor @Suite(.enabled(if: modelIsReady)) struct StreamingIntoTheEditorTests {
    @Test func aResponseStreamsIntoTheEditor() async throws {
        let controller = EditorController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400), styleMask: [.titled], backing: .buffered,
            defer: false)
        defer { withExtendedLifetime(window) {} }
        controller.scrollView.frame = window.contentView?.bounds ?? .zero
        window.contentView?.addSubview(controller.scrollView)
        let start = "# Spells\n\n"
        controller.load(start, flavor: .markdown)
        let request = IntelligenceRequest(
            instructions: "You write one short sentence.", text: "Write a sentence about ink.", temperature: 0)
        controller.streamInsertion(
            IntelligenceService.shared.stream(request), replacing: NSRange(location: start.utf16.count, length: 0),
            actionName: "Test Response")
        for _ in 0..<500 where !controller.isAwaitingKeep {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.isAwaitingKeep)
        controller.keepStreamedText()
        #expect(controller.text.count > start.count)
        controller.textView.undoManager?.undo()
        #expect(controller.text == start)
    }
}
#endif
