import AppKit
import GrimoireCore
import MetricKit
import SwiftUI

/// Receives the crash and hang diagnostics macOS delivers through MetricKit and hands each
/// payload's JSON to the `DiagnosticReportStore`. Nothing is sent anywhere.
final class DiagnosticReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    /// MetricKit keeps no strong reference to its subscribers, so the app holds this one
    /// for as long as it runs.
    private static let shared = DiagnosticReporter(store: .standard)

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
            try? store.save(payload.jsonRepresentation(), endDate: payload.timeStampEnd)
        }
    }
}

/// Help ▸ Show Diagnostic Reports.
struct DiagnosticCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Show Diagnostic Reports") {
                let store = DiagnosticReportStore.standard
                try? store.ensureFolder()
                NSWorkspace.shared.open(store.folder)
            }
        }
    }
}
