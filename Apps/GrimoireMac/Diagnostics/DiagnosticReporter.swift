import AppKit
import GrimoireCore
import MetricKit
import OSLog
import SwiftUI

/// Receives the crash and hang diagnostics macOS delivers through MetricKit and hands each
/// payload's JSON to the `DiagnosticReportStore`. Nothing is sent anywhere.
final class DiagnosticReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    /// MetricKit keeps no strong reference to its subscribers, so the app holds this one
    /// for as long as it runs.
    private static let shared = DiagnosticReporter(store: .standard)

    private static let log = Logger(subsystem: "computer.srcery.grimoire", category: "diagnostics")

    private let store: DiagnosticReportStore

    init(store: DiagnosticReportStore) {
        self.store = store
    }

    /// Subscribes at launch.
    static func start() {
        MXMetricManager.shared.add(shared)
    }

    /// Called on a background queue.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            do {
                try store.save(payload.jsonRepresentation(), endDate: payload.timeStampEnd)
            } catch {
                Self.log.error("Could not save a diagnostic report: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Help ▸ Show Diagnostic Reports.
struct DiagnosticCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Show Diagnostic Reports") { Self.show() }
        }
    }

    @MainActor
    private static func show() {
        let store = DiagnosticReportStore.standard
        do {
            try store.ensureFolder()
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "Can't open the diagnostic reports folder")
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return
        }
        NSWorkspace.shared.open(store.folder)
    }
}
