import AppKit
import GrimoireCore
import GrimoireEditor
import SwiftUI

@main
struct GrimoireMacApp: App {
    @State private var library = ProjectLibrary()

    init() {
        BrandFont.register()
    }

    var body: some Scene {
        WindowGroup(id: "project") {
            ContentView()
                .environment(library)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Grimoire") { showAboutPanel() }
            }
            GrimoireCommands()
        }
        Settings {
            SettingsView()
        }
    }

    private func showAboutPanel() {
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
