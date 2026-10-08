import AppKit
import GrimoireCore
import GrimoireEditor
import SwiftUI

@main
struct GrimoireMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = ExternalOpens.shared.library
    @Environment(\.openWindow) private var openWindow

    init() {
        BrandFont.register()
        DiagnosticReporter.start()
    }

    var body: some Scene {
        // `ExternalOpens` opens windows for files from Finder, which can arrive before any
        // window has appeared to hand it this action.
        // swiftlint:disable:next redundant_discardable_let
        let _ = ExternalOpens.shared.openWindow = { openWindow(id: "project") }
        WindowGroup(id: "project") {
            ContentView()
                .environment(library)
        }
        // Files from Finder are routed by `ExternalOpens`; SwiftUI would open a window for each.
        .handlesExternalEvents(matching: [])
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Grimoire") { AboutPanel.show() }
            }
            TextEditingCommands()
            GrimoireCommands()
            DiagnosticCommands()
        }
        Settings {
            SettingsView()
                .environment(library)
        }
    }
}

/// The About box, with the brand's credit line.
@MainActor
enum AboutPanel {
    static func show() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let line = String(localized: "Grimoire \(version), bound at srcery.computer")
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: line,
                attributes: [
                    .font: BrandFont.ctFont(.metadata),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]),
            .init(rawValue: "Copyright"): "",
        ])
    }
}
