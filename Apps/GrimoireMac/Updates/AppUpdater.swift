import Observation
import Sparkle
import SwiftUI

/// Wraps Sparkle's standard updater: it starts checking in the background when the
/// app launches, and exposes whether the "Check for Updates…" command may run.
/// The feed URL and public key come from the app's Info.plist.
@MainActor
@Observable
final class AppUpdater {
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        // Sparkle turns this off while a check or an update session is running.
        let updater = controller.updater
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let canCheck = change.newValue ?? false
            Task { @MainActor in self?.canCheckForUpdates = canCheck }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// The "Check for Updates…" item under the About item in the app menu.
struct UpdateCommands: Commands {
    let updater: AppUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}
