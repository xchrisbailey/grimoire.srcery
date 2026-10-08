import Observation
import Sparkle
import SwiftUI

/// Wraps Sparkle's standard updater: it starts checking in the background when the
/// app launches, and says whether the "Check for Updates…" command may run.
/// The feed URL and public key come from the app's Info.plist.
@MainActor
@Observable
final class AppUpdater {
    /// False while a check is running, whether the user started it or Sparkle did in the
    /// background, and while its result is on screen. Sparkle alone leaves the command on
    /// during a user-started check, so a second click only brings the first one forward.
    var canCheckForUpdates: Bool { sparkleAllowsCheck && !userCheckIsRunning }

    private var sparkleAllowsCheck = false
    private var userCheckIsRunning = false

    @ObservationIgnored private let cycleEnd = UpdateCycleObserver()
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: cycleEnd, userDriverDelegate: nil)
        cycleEnd.onFinish = { [weak self] in self?.userCheckIsRunning = false }
        let updater = controller.updater
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let canCheck = change.newValue ?? false
            Task { @MainActor in self?.sparkleAllowsCheck = canCheck }
        }
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        userCheckIsRunning = true
        controller.checkForUpdates(nil)
    }
}

/// Hears from Sparkle when an update cycle, started by the user or not, is over.
private final class UpdateCycleObserver: NSObject, SPUUpdaterDelegate {
    @MainActor var onFinish: () -> Void = {}

    func updater(
        _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?
    ) {
        Task { @MainActor in onFinish() }
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
