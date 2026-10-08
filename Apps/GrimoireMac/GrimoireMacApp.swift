import AppKit
import GrimoireCore
import GrimoireEditor
import SwiftUI

@main
struct GrimoireMacApp: App {
    @State private var library = ProjectLibrary()

    init() {
        BrandFont.register()
        DiagnosticReporter.start()
    }

    var body: some Scene {
        WindowGroup(id: "project") {
            ContentView()
                .environment(library)
        }
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
